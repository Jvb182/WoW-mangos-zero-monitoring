# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY main.go ./

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -o wow-exporter .

# Runtime stage
FROM alpine:latest

# Install procps for pgrep command
RUN apk --no-cache add procps

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/wow-exporter .

# Expose metrics port
EXPOSE 9101

# Run the exporter
CMD ["./wow-exporter"]