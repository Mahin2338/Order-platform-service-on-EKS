# image being used is golang:1.26.10
FROM golang:1.26.10@sha256:670bb5aa5349ae03b8516764718486f4f16399134bdc9acd0c46a23f043ab05c AS build

WORKDIR /app

ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64

COPY go.mod go.sum ./

ENV GOTOOLCHAIN=local

RUN go mod download && go mod verify

COPY main.go ./

RUN go build -mod=readonly -trimpath -buildvcs=false -o shipping-service .

# image being used is gcr.io/distroless/static-debian13
FROM gcr.io/distroless/static-debian13@sha256:963fa6c544fe5ce420f1f54fb88b6fb01479f054c8056d0f74cc2c6000df5240

WORKDIR /app

COPY --from=build /app/shipping-service ./

# Explicitly run the application as an unprivileged numeric user.
USER 65532:65532

CMD ["./shipping-service"]
