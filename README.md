# NAT-PMP HTTP API Client

A lightweight Docker container that maintains NAT-PMP port mappings by sending periodic refresh requests to the [natpmp-http-api](https://github.com/BohdanTkachenko/natpmp-http-api) service.

## Features

- **Automatic refresh management** - Maintains port mappings by sending periodic renewal requests
- **Multi-protocol support** - Request TCP, UDP, or both protocols simultaneously
- **Configurable timing** - Set custom duration and refresh intervals
- **Bearer token authentication** - Secure communication with the NAT-PMP API
- **Minimal footprint** - Only ~9 MB Alpine-based container
- **Multi-architecture** - Supports amd64, arm64, armv7, riscv64

## Quick Start

```bash
docker run -d \
  --name natpmp-refresh \
  -e NATPMP_SERVICE=natpmp-service:8080 \
  -e INTERNAL_PORT=6881 \
  -e API_TOKEN=your-secret-token \
  ghcr.io/YOUR_USERNAME/natpmp-http-api-client:latest
```

## Configuration

All configuration is done via environment variables:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NATPMP_SERVICE` | ✅ | - | NAT-PMP API service host:port (e.g., `natpmp-service:8080`) |
| `INTERNAL_PORT` | ✅ | - | Internal port to forward (e.g., `6881`) |
| `API_TOKEN` | | - | Bearer token for API authentication (recommended) |
| `ENABLE_TCP` | | `true` | Enable TCP protocol forwarding (`true`/`false`) |
| `ENABLE_UDP` | | `true` | Enable UDP protocol forwarding (`true`/`false`) |
| `DURATION` | | `60` | Mapping duration in seconds |
| `REFRESH_INTERVAL` | | `45` | Seconds between renewal requests (should be ~75% of duration) |

## Examples

### Docker Compose

```yaml
services:
  natpmp-refresh:
    image: ghcr.io/YOUR_USERNAME/natpmp-http-api-client:latest
    environment:
      NATPMP_SERVICE: natpmp-service:8080
      INTERNAL_PORT: 6881
      API_TOKEN: your-secret-token
      ENABLE_TCP: true
      ENABLE_UDP: true
    restart: unless-stopped
```

### Kubernetes Sidecar

```yaml
containers:
- name: my-app
  image: my-app:latest
  ports:
  - containerPort: 6881

- name: natpmp-refresh
  image: ghcr.io/YOUR_USERNAME/natpmp-http-api-client:latest
  env:
  - name: NATPMP_SERVICE
    value: "natpmp-service:8080"
  - name: INTERNAL_PORT
    value: "6881"
  - name: API_TOKEN
    valueFrom:
      secretKeyRef:
        name: natpmp-secret
        key: token
  - name: ENABLE_TCP
    value: "true"
  - name: ENABLE_UDP
    value: "true"
  resources:
    limits:
      cpu: 50m
      memory: 32Mi
```

## Building

### Using Pre-built Images

Multi-architecture images are automatically built and published to GitHub Container Registry:

```bash
docker pull ghcr.io/YOUR_USERNAME/natpmp-http-api-client:latest
```

### Building Locally

```bash
docker build -t natpmp-refresh:latest .

docker run --rm \
  -e NATPMP_SERVICE=localhost:8080 \
  -e INTERNAL_PORT=6881 \
  natpmp-refresh:latest
```

## How It Works

1. On startup, validates required environment variables
2. Enters an infinite loop that:
   - Sends POST requests to the NAT-PMP API's `/forward` endpoint for each protocol
   - Includes authentication header if `API_TOKEN` is set
   - Logs the response (external port assignment or error)
   - Sleeps for `REFRESH_INTERVAL` seconds before the next renewal
3. The refresh interval should be set to ~75% of the duration to ensure mappings don't expire

### Example Output

```
Starting NAT-PMP refresh service...
Service: http://natpmp-service:8080/forward
Internal Port: 6881
Protocols: tcp,udp
Duration: 60s
Refresh Interval: 45s

[2025-11-02 10:00:00] Requesting NAT-PMP port mappings for port 6881...
  → tcp mapping...
  ✓ tcp mapping successful: {"internal_port":6881,"external_port":62610,"protocol":"tcp","duration":60}
  → udp mapping...
  ✓ udp mapping successful: {"internal_port":6881,"external_port":62610,"protocol":"udp","duration":60}
  Sleeping 45s until next renewal...
```

## Use Cases

- **BitTorrent clients** - Keep seeding ports open through VPN
- **Game servers** - Maintain player connectivity
- **Remote access** - Keep SSH/RDP ports forwarded
- **Kubernetes deployments** - Sidecar for any app needing port forwarding

## Requirements

- NAT-PMP HTTP API service running and accessible
- VPN connection with NAT-PMP support (e.g., ProtonVPN, Private Internet Access)

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
