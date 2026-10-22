package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

// Event represents a message from SQS
type Event struct {
	Type      string                 `json:"type"`
	Payload   map[string]interface{} `json:"payload"`
	Timestamp string                 `json:"timestamp"`
}

type QueueMessage struct {
	Body          string
	ReceiptHandle string
}

var sqsClient *sqs.Client

func main() {
	sqsQueue := os.Getenv("SQS_QUEUE_URL")
	if sqsQueue == "" {
		log.Fatal("SQS_QUEUE_URL is required")
	}

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Fatalf("failed to load AWS config: %v", err)
	}
	sqsClient = sqs.NewFromConfig(cfg)

	// Internal service URLs for event-driven calls
	services := map[string]string{
		"inventory":    getEnv("INVENTORY_SERVICE_URL", "http://inventory-service:8082"),
		"payment":      getEnv("PAYMENT_SERVICE_URL", "http://payment-service:8083"),
		"notification": getEnv("NOTIFICATION_SERVICE_URL", "http://notification-service:8084"),
		"shipping":     getEnv("SHIPPING_SERVICE_URL", "http://shipping-service:8085"),
		"order":        getEnv("ORDER_SERVICE_URL", "http://order-service:8081"),
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Health check endpoint
	go func() {
		mux := http.NewServeMux()
		mux.HandleFunc("/livez", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "worker"})
		})
		port := getEnv("HEALTH_PORT", "8090")
		log.Printf("Worker health check on :%s", port)
		http.ListenAndServe(":"+port, mux)
	}()

	// Graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigChan
		log.Println("Shutting down worker...")
		cancel()
	}()

	log.Println("Worker started, polling SQS for events...")
	pollAndProcess(ctx, sqsQueue, services)
}

func pollAndProcess(ctx context.Context, queueURL string, services map[string]string) {
	client := &http.Client{Timeout: 10 * time.Second}

	for {
		select {
		case <-ctx.Done():
			log.Println("Worker stopped")
			return
		default:
			messages := receiveSQSMessages(ctx, queueURL)

			for _, message := range messages {
				var event Event
				if err := json.Unmarshal([]byte(message.Body), &event); err != nil {
					log.Printf("Failed to parse event: %v", err)
					continue
				}

				log.Printf("Processing event: %s", event.Type)

				if err := handleEvent(client, services, event); err != nil {
					log.Printf("Failed to handle event %s: %v", event.Type, err)
					// In production: don't delete from SQS, let it retry or go to DLQ
					continue
				}

				log.Printf("Successfully processed: %s", event.Type)
				deleteSQSMessage(ctx, queueURL, message.ReceiptHandle)
			}

			if len(messages) == 0 {
				time.Sleep(5 * time.Second)
			}
		}
	}
}

func handleEvent(client *http.Client, services map[string]string, event Event) error {
	switch event.Type {

	case "order.created":
		log.Printf("  -> Reserving inventory for order")
		if err := postJSON(client, services["inventory"]+"/reserve", map[string]interface{}{
			"order_id": event.Payload["order_id"],
			"items":    event.Payload["items"],
		}); err != nil {
			log.Printf("  -> Inventory reservation failed: %v", err)
			_ = putJSON(client, services["order"]+"/status", map[string]interface{}{
				"order_id":   event.Payload["order_id"],
				"new_status": "cancelled",
			})
			return nil
		}

		log.Printf("  -> Processing payment")
		if err := postJSON(client, services["payment"]+"/charge", map[string]interface{}{
			"order_id":    event.Payload["order_id"],
			"customer_id": event.Payload["customer_id"],
			"amount":      event.Payload["total"],
			"currency":    event.Payload["currency"],
			"method":      "card",
		}); err != nil {
			log.Printf("  -> Payment failed: %v", err)
			_ = postJSON(client, services["inventory"]+"/release", map[string]interface{}{
				"order_id": event.Payload["order_id"],
			})
			_ = putJSON(client, services["order"]+"/status", map[string]interface{}{
				"order_id":   event.Payload["order_id"],
				"new_status": "cancelled",
			})
			_ = postJSON(client, services["notification"]+"/send", map[string]interface{}{
				"recipient": event.Payload["customer_id"],
				"channel":   "email",
				"template":  "payment_failed",
				"data":      event.Payload,
			})
			return nil
		}

		log.Printf("  -> Sending order confirmation")
		_ = postJSON(client, services["notification"]+"/send", map[string]interface{}{
			"recipient": event.Payload["customer_id"],
			"channel":   "email",
			"template":  "order_confirmed",
			"data":      event.Payload,
		})

		log.Printf("  -> Confirming order")
		return putJSON(client, services["order"]+"/status", map[string]interface{}{
			"order_id":   event.Payload["order_id"],
			"new_status": "confirmed",
		})

	case "order.status_changed":
		newStatus, _ := event.Payload["new_status"].(string)

		switch newStatus {
		case "processing":
			log.Printf("  -> Creating shipment for order")
			return postJSON(client, services["shipping"]+"/shipments", map[string]interface{}{
				"order_id":       event.Payload["order_id"],
				"recipient_name": event.Payload["customer_id"],
				"address_line1":  "Unknown",
				"city":           "Unknown",
				"postcode":       "UNKNOWN",
				"country":        "GB",
				"weight_kg":      1,
			})

		case "shipped":
			log.Printf("  -> Sending shipping notification")
			return postJSON(client, services["notification"]+"/send", map[string]interface{}{
				"recipient": event.Payload["customer_id"],
				"channel":   "email",
				"template":  "order_shipped",
				"data":      event.Payload,
			})

		case "delivered":
			log.Printf("  -> Sending delivery notification")
			return postJSON(client, services["notification"]+"/send", map[string]interface{}{
				"recipient": event.Payload["customer_id"],
				"channel":   "email",
				"template":  "order_delivered",
				"data":      event.Payload,
			})

		case "cancelled":
			log.Printf("  -> Releasing inventory reservation")
			if err := postJSON(client, services["inventory"]+"/release", map[string]interface{}{
				"order_id": event.Payload["order_id"],
			}); err != nil {
				return err
			}

			if event.Payload["payment_id"] == nil {
				return nil
			}
			log.Printf("  -> Processing refund")
			return postJSON(client, services["payment"]+"/refund", map[string]interface{}{
				"payment_id": fmt.Sprintf("%v", event.Payload["payment_id"]),
				"reason":     "order cancelled",
			})
		}

	case "payment.completed":
		log.Printf("  -> Payment successful")

	case "payment.failed":
		log.Printf("  -> Payment failed")

	case "shipment.created":
		log.Printf("  -> Shipment created")

	case "shipment.delivered":
		log.Printf("  -> Shipment delivered, updating order")
		return putJSON(client, services["order"]+"/status", map[string]interface{}{
			"order_id":   event.Payload["order_id"],
			"new_status": "delivered",
		})

	default:
		log.Printf("  -> Unknown event type: %s (skipping)", event.Type)
	}

	return nil
}

func receiveSQSMessages(ctx context.Context, queueURL string) []QueueMessage {
	resp, err := sqsClient.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            &queueURL,
		MaxNumberOfMessages: 10,
		WaitTimeSeconds:     20,
	})
	if err != nil {
		log.Printf("Failed to receive SQS messages: %v", err)
		return nil
	}

	messages := make([]QueueMessage, 0, len(resp.Messages))
	for _, msg := range resp.Messages {
		if msg.Body == nil || msg.ReceiptHandle == nil {
			continue
		}
		messages = append(messages, QueueMessage{
			Body:          *msg.Body,
			ReceiptHandle: *msg.ReceiptHandle,
		})
	}
	return messages
}

func deleteSQSMessage(ctx context.Context, queueURL, receiptHandle string) {
	if _, err := sqsClient.DeleteMessage(ctx, &sqs.DeleteMessageInput{
		QueueUrl:      &queueURL,
		ReceiptHandle: &receiptHandle,
	}); err != nil {
		log.Printf("Failed to delete SQS message: %v", err)
	}
}

func postJSON(client *http.Client, url string, payload interface{}) error {
	return sendJSON(client, http.MethodPost, url, payload)
}

func putJSON(client *http.Client, url string, payload interface{}) error {
	return sendJSON(client, http.MethodPut, url, payload)
}

func sendJSON(client *http.Client, method, url string, payload interface{}) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	req, err := http.NewRequest(method, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("%s %s returned %s", method, url, resp.Status)
	}
	return nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
