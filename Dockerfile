FROM golang:1.25-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o wow-exporter main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/wow-exporter .
EXPOSE 8080
CMD ["./wow-exporter"]