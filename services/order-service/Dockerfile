# image being used is golang:1.26.3
FROM golang@sha256:2d6c80227255c3112a4d08e67ba98e58efd3846daf15d9d7d4c389565d881b1a AS build

WORKDIR /app

ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64

COPY go.mod go.sum ./

RUN go mod download

COPY main.go ./

RUN go build -o order-service .

# image being used is gcr.io/distroless/static-debian13
FROM gcr.io/distroless/static-debian13@sha256:963fa6c544fe5ce420f1f54fb88b6fb01479f054c8056d0f74cc2c6000df5240

WORKDIR /app

COPY --from=build /app/order-service ./

# distroless image runs as a non root user by default (uid 65532)

CMD ["./order-service"]
