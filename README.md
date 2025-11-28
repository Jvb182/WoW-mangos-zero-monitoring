# WoW MaNGOS Zero Monitoring Stack

A complete monitoring solution for MaNGOS Zero World of Warcraft private servers, featuring real-time metrics, system monitoring, and log aggregation.

## Features

- **Server Status Monitoring** - Track if your WoW server is up/down in real-time
- **System Metrics** - CPU, memory, disk usage, and network stats via Node Exporter
- **Log Aggregation** - Centralized logging for realm-list, world-server, gamemaster actions, and Eluna errors
- **Beautiful Dashboards** - Pre-configured Grafana dashboards for at-a-glance monitoring
- **Alerting** - Set up alerts for server downtime or critical errors (coming soon)

## Architecture

- **Grafana** - Visualization and dashboards
- **Prometheus** - Metrics collection and storage
- **Loki** - Log aggregation
- **Promtail** - Log shipping agent
- **Node Exporter** - System metrics collection
- **WoW Exporter** - Custom Go exporter for WoW server status

## Prerequisites

- Docker and Docker Compose
- MaNGOS Zero server installed
- Basic understanding of Docker networking

## Quick Start


### 1. Clone and Setup
```bash
git clone https://github.com/yourusername/WoW-mangos-zero-monitoring.git
cd WoW-mangos-zero-monitoring
./setup.sh  # Sets directory permissions
```

### 2. Configure Environment Variables

Copy the example environment file and customize for your setup:
```bash
cp .env.example .env
nano .env
```

**Required variables:**
- `MANGOS_LOG_PATH` - Path to your MaNGOS log directory
- `MANGOS_PROCESS_NAME` - Your world server process name (default: `mangosd`)

**Optional variables:**
- `GRAFANA_PORT` - Grafana web UI port (default: 3000)
- `GF_LOG_LEVEL` - Log level (default: info)

### 3. Update WoW Exporter Process Name (if needed)

If your world server process isn't named `mangosd`, edit `main.go`:
```go
cmd := exec.Command("pgrep", "-x", "your-process-name")
```

### 4. Create Required Directories
```bash
mkdir -p grafana prometheus-data loki-data
sudo chown -R 472:472 grafana/
sudo chown -R 10001:10001 loki-data/
```

### 5. Start the Stack
```bash
docker compose up -d
```

### 6. Access Grafana

Open your browser to `http://localhost:3000`

**Default credentials:**
- Username: `admin`
- Password: `admin`

You'll be prompted to change the password on first login.

### 7. Add Data Sources

**Prometheus:**
1. Go to Configuration → Data Sources
2. Add Prometheus
3. URL: `http://prometheus:9090`
4. Save & Test

**Loki:**
1. Add Loki data source
2. URL: `http://loki:3100`
3. Save & Test

### 8. Import Dashboards

**Node Exporter Dashboard:**
1. Go to Dashboards → Import
2. Enter ID: `1860`
3. Select Prometheus data source
4. Import

**Create WoW Server Dashboard:**
1. Create new dashboard
2. Add panel with query: `wow_server_up`
3. Set visualization to "Stat"
4. Thresholds: 0 = red, 1 = green

**View Logs:**
1. Go to Explore
2. Select Loki data source
3. Query: `{job="wow_server"}`

## Configuration Files

### Prometheus (`prometheus/prometheus.yml`)

Scrapes metrics from Node Exporter and WoW Exporter every 15 seconds. Retains data for 30 days.

### Loki (`loki/loki-config.yaml`)

Stores logs with 7-day retention (168 hours).

### Promtail (`promtail/promtail-config.yaml`)

Tails the following log files:
- `world-server.log`
- `realm-list.log`
- `ElunaErrors.log`
- `world-gamemaster.log`

To monitor additional logs, edit the `__path__` in `promtail-config.yaml`.

## Custom WoW Exporter

The WoW exporter is a simple Go application that checks if your MaNGOS server process is running and exposes it as a Prometheus metric.

**Metric exposed:**
- `wow_server_up` - Returns 1 if server is running, 0 if down

**How it works:**
- Uses `pgrep` to check for the process
- Runs with host PID namespace to see all processes
- Exposes metrics on port 8080

## Port Reference

| Service | Port | Purpose |
|---------|------|---------|
| Grafana | 3000 | Web UI |
| Prometheus | 9090 | Metrics database (optional direct access) |
| Loki | 3100 | Log aggregation (optional direct access) |
| Node Exporter | 9100 | System metrics (optional direct access) |
| WoW Exporter | 8080 | WoW server status |

## Troubleshooting

### Logs aren't showing up in Grafana
```bash
# Check Promtail is reading logs
docker logs promtail

# Verify log file permissions
ls -la /path/to/your/mangos/bin/*.log

# Test Loki connection
curl http://localhost:3100/ready
```

### WoW server shows as down but it's running
```bash
# Check the process name
ps aux | grep -i mangos

# Update main.go with correct process name
# Rebuild: docker compose up -d --build wow-exporter
```

### Permission denied errors
```bash
# Fix Grafana permissions
sudo chown -R 472:472 grafana/

# Fix Loki permissions
sudo chown -R 10001:10001 loki-data/
```

## Customization

### Monitor Additional Logs

Edit `promtail/promtail-config.yaml`:
```yaml
__path__: /var/log/wow/{world-server,realm-list,ElunaErrors,world-gamemaster,your-new-log}.log
```

### Change Data Retention

**Prometheus** - Edit `docker-compose.yaml`:
```yaml
command:
  - '--storage.tsdb.retention.time=60d'  # Change from 30d to 60d
```

**Loki** - Edit `loki/loki-config.yaml`:
```yaml
limits_config:
  retention_period: 336h  # 14 days instead of 7
```

### Add Alerting

Configure Prometheus alerting rules or Grafana alerts based on metrics like:
- `wow_server_up == 0` (server down)
- `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.1` (low memory)

## Using with Traefik

If you're using Traefik as a reverse proxy, add Grafana to both networks:
```yaml
grafana:
  networks:
    - traefik-network
    - monitoring-network
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.grafana.rule=Host(`grafana.yourdomain.com`)"
    - "traefik.http.services.grafana.loadbalancer.server.port=3000"
    # Add TLS configuration
```

## Development

### Rebuilding WoW Exporter
```bash
# Make changes to main.go
docker compose up -d --build wow-exporter
docker logs wow-exporter
```

### Testing Locally

You can develop the Go exporter locally:
```bash
go mod download
go run main.go
# Access metrics at http://localhost:8080/metrics
```

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - see LICENSE file for details

## Acknowledgments

- [MaNGOS Project](https://getmangos.eu/)
- [Prometheus](https://prometheus.io/)
- [Grafana Labs](https://grafana.com/)
- Built with guidance from Claude :)

## Support

For issues or questions:
- Open a GitHub issue
- Check MaNGOS forums for server-specific questions

---

**Note:** This monitoring stack is designed for private server use. Ensure you comply with all applicable laws and game terms of service when running private servers.