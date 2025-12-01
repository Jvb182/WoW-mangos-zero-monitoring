# WoW MaNGOS Zero Monitoring Stack

A complete monitoring solution for MaNGOS Zero World of Warcraft private servers, featuring real-time server metrics, database performance monitoring, and log aggregation.

## What This Does

Monitor your MaNGOS server with professional-grade tools:
- **Server Status** - Real-time monitoring of world server and realm server processes
- **Player Metrics** - Track online players, logins, and activity
- **Database Performance** - Monitor MySQL query rates, connections, slow queries, and buffer pool efficiency
- **System Metrics** - CPU, memory, disk usage, and network stats
- **Log Aggregation** - Centralized viewing of server logs, errors, GM commands, and player events
- **Beautiful Dashboards** - Pre-configured Grafana dashboard with all key metrics

## Architecture

**Your Existing Setup (Host Machine):**
- MaNGOS Server (mangosd and realmd processes)
- MySQL/MariaDB Database (mangos0, character0, realmd databases)

**Monitoring Stack (Runs in Docker):**
- **Grafana** - Visualization and dashboards (accessible at http://localhost:3000)
- **Prometheus** - Metrics collection and time-series storage
- **Loki** - Log aggregation and storage
- **Promtail** - Reads logs from your MaNGOS server
- **Node Exporter** - Collects system metrics (CPU, RAM, disk)
- **MySQL Exporter** - Collects database performance metrics
- **WoW Exporter** - Custom Go service that monitors MaNGOS processes and player count

The monitoring stack runs in Docker containers but connects to your existing MaNGOS installation on the host.

## Prerequisites

- **Docker and Docker Compose** installed
- **MaNGOS Zero server** running on the host machine (not in Docker)
- **MySQL/MariaDB database** running on the host machine (not in Docker)
- **Root/sudo access** for configuration and permissions
- **Basic Linux knowledge** (editing config files, managing services)

## Installation

You have two options: use the automated setup script or follow the manual steps.

### Option 1: Automated Setup (Recommended)
```bash
git clone <your-repo-url>
cd WoW-mangos-zero-monitoring
chmod +x setup.sh
./setup.sh
```

The setup script will guide you through:
1. Creating and configuring the `.env` file
2. Setting directory permissions
3. Configuring log file access
4. Checking MySQL network configuration
5. Creating a read-only MySQL monitoring user
6. Testing all connections

After setup completes, restart the stack:
```bash
docker compose restart
```

### Option 2: Manual Setup

If you prefer to understand and configure everything manually, follow these steps:

#### Step 1: Clone and Configure
```bash
git clone <your-repo-url>
cd WoW-mangos-zero-monitoring
cp .env.example .env
nano .env
```

Configure these required variables in `.env`:
```bash
# Path to your MaNGOS log directory
MANGOS_LOG_PATH=/home/mangos/mangos/zero/bin

# Process names (verify with: ps aux | grep mangos)
MANGOS_PROCESS_NAME=mangosd
REALM_PROCESS_NAME=realmd

# MySQL connection details (will be configured in Step 5)
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_WORLD_DB=mangos0
MYSQL_CHAR_DB=character0
MYSQL_REALM_DB=realmd
MYSQL_USER=mangos_monitor
MYSQL_PASSWORD=<will-be-generated>
```

#### Step 2: Create Data Directories
```bash
mkdir -p grafana/data prometheus/data loki/data mysql-exporter
```

#### Step 3: Set Directory Permissions

These directories need specific ownership for the containerized services:
```bash
# Grafana runs as UID 472
sudo chown -R 472:472 grafana/data/

# Loki runs as UID 10001
sudo chown -R 10001:10001 loki/data/

# Prometheus runs as UID 65534 (nobody)
sudo chown -R 65534:65534 prometheus/data/
```

#### Step 4: Configure Log File Access

Promtail needs to read your MaNGOS log files. Choose one option:

**Option A: Make logs world-readable (easier)**
```bash
sudo chmod -R o+r /home/mangos/mangos/zero/bin/*.log
sudo chmod o+rx /home/mangos/mangos/zero/bin
```

**Option B: Run Promtail as mangos user (more secure)**
```bash
# Get the mangos user's UID
id -u mangos

# Edit docker-compose.yaml and add under the promtail service:
#   user: "1003:1003"  # Replace with actual UID:GID
```

#### Step 5: Configure MySQL for Docker Access

**CRITICAL:** MySQL must be configured to accept connections from Docker containers.

##### 5a. Configure MySQL Bind Address

MySQL by default only listens on `127.0.0.1` (localhost), which Docker containers cannot reach.

**Check current bind address:**
```bash
sudo ss -tlnp | grep 3306
```

If you see `127.0.0.1:3306`, you need to change it:
```bash
# Edit MySQL/MariaDB config
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf
# or for MySQL: sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
```

Find the `[mysqld]` section and change:
```ini
# Change this:
bind-address = 127.0.0.1

# To this:
bind-address = 0.0.0.0
```

**Restart MySQL:**
```bash
sudo systemctl restart mariadb
# or: sudo systemctl restart mysql

# Verify it's listening on all interfaces:
sudo ss -tlnp | grep 3306
# Should show: 0.0.0.0:3306
```

##### 5b. Configure Firewall

Docker containers need firewall access to MySQL. First, start the monitoring stack to detect the network:
```bash
docker compose up -d
```

Find your Docker gateway IP:
```bash
docker network inspect auto-monitor_monitoring-network | grep Gateway
# Note the IP (e.g., 172.xx.x.x)

# The subnet will be the first two octets: 172.x.x.x/16
```

**Add firewall rule:**
```bash
# Replace 172.x.x.x/16 with your actual subnet if different
sudo ufw allow from 172.xx.x.x/16 to any port 3306

# Verify
sudo ufw status | grep 3306
```

**Alternative for iptables:**
```bash
sudo iptables -A INPUT -s 172.xx.x.x/16 -p tcp --dport 3306 -j ACCEPT
```

##### 5c. Create MySQL Monitoring User
```bash
mysql -u root -p
```

In MySQL, run these commands (replace `YourSecurePassword` with a strong password):
```sql
-- Create monitoring user
CREATE USER 'mangos_monitor'@'localhost' IDENTIFIED BY 'YourSecurePassword';
CREATE USER 'mangos_monitor'@'%' IDENTIFIED BY 'YourSecurePassword';

-- Grant read-only permissions on all MaNGOS databases
GRANT SELECT ON mangos0.* TO 'mangos_monitor'@'localhost';
GRANT SELECT ON character0.* TO 'mangos_monitor'@'localhost';
GRANT SELECT ON realmd.* TO 'mangos_monitor'@'localhost';
GRANT SELECT ON mangos0.* TO 'mangos_monitor'@'%';
GRANT SELECT ON character0.* TO 'mangos_monitor'@'%';
GRANT SELECT ON realmd.* TO 'mangos_monitor'@'%';

-- Grant process and replication permissions
GRANT PROCESS ON *.* TO 'mangos_monitor'@'localhost';
GRANT PROCESS ON *.* TO 'mangos_monitor'@'%';
GRANT REPLICATION CLIENT ON *.* TO 'mangos_monitor'@'localhost';
GRANT REPLICATION CLIENT ON *.* TO 'mangos_monitor'@'%';

FLUSH PRIVILEGES;
exit
```

**Update your `.env` file** with the password you created.

##### 5d. Create MySQL Exporter Config
```bash
nano mysql-exporter/.my.cnf
```

Add (using your Docker gateway IP from step 5b):
```ini
[client]
user=mangos_monitor
password=YourSecurePassword
host=172.xx.xx.xx  # Your gateway IP
port=3306
protocol=tcp
```

Set permissions:
```bash
chmod 600 mysql-exporter/.my.cnf
```

#### Step 6: Start the Stack
```bash
# If not already started:
docker compose up -d

# Or restart with new configuration:
docker compose down
docker compose up -d

# Check status:
docker compose ps

# View logs:
docker compose logs -f
```

#### Step 7: Verify Everything Works
```bash
# Check mysql-exporter can connect
docker logs mysql-exporter
# Should see no errors

# Check wow-exporter metrics
curl http://localhost:9101/metrics | grep wow_
# Should show wow_server_up, wow_realm_up, wow_players_online

# Check mysql metrics
curl http://localhost:9104/metrics | grep mysql_global_status_threads_connected
# Should show current connection count

# Check Prometheus targets
docker exec prometheus wget -qO- http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'
# All should show "up"
```

## Accessing Grafana

1. Open your browser to: **http://localhost:3000**
2. Default credentials: **admin / admin**
3. You'll be prompted to change the password on first login

The pre-configured dashboard is already loaded and will show:
- Server status (world server and realm server up/down)
- Players online
- MySQL performance metrics
- Log streams

## Troubleshooting

### MySQL Exporter Shows "Connection Refused"

**Problem:** `docker logs mysql-exporter` shows connection errors

**Solutions:**
1. Verify MySQL bind-address is `0.0.0.0`: `sudo ss -tlnp | grep 3306`
2. Check firewall rule exists: `sudo ufw status | grep 3306`
3. Test from container: `docker exec mysql-exporter mysql --defaults-file=/etc/.my.cnf -e "SELECT 1;"`
4. Verify gateway IP is correct in `mysql-exporter/.my.cnf`

### No Logs Appearing in Grafana

**Problem:** "Live Server Logs" panel shows no data

**Solutions:**
1. Check Promtail is reading files: `docker logs promtail`
2. Verify log permissions: `ls -la /path/to/mangos/bin/*.log`
3. Check logs exist and are being written to
4. Verify `MANGOS_LOG_PATH` in `.env` is correct

### WoW Server Shows as Down When It's Running

**Problem:** Dashboard shows "DOWN" but server is running

**Solutions:**
1. Verify process name: `ps aux | grep mangos`
2. Check `MANGOS_PROCESS_NAME` in `.env` matches exactly
3. View exporter logs: `docker logs wow-exporter`
4. Rebuild exporter: `docker compose up -d --build wow-exporter`

### Prometheus Not Scraping Metrics

**Problem:** Metrics show "No data" in Grafana

**Solutions:**
1. Check Prometheus targets: http://localhost:9090/targets
2. All targets should show "UP" status
3. Check container networking: `docker network inspect auto-monitor_monitoring-network`
4. Restart Prometheus: `docker compose restart prometheus`

### Permission Denied Errors

**Problem:** Containers fail to start with permission errors

**Solutions:**
```bash
# Fix Grafana
sudo chown -R 472:472 grafana/data/

# Fix Loki
sudo chown -R 10001:10001 loki/data/

# Fix Prometheus
sudo chown -R 65534:65534 prometheus/data/

# Restart
docker compose restart
```

## Configuration

### Changing Data Retention

**Prometheus (default: 30 days)**

Edit `docker-compose.yaml`:
```yaml
prometheus:
  command:
    - '--storage.tsdb.retention.time=60d'  # Change to 60 days
```

**Loki (default: 7 days)**

Edit `loki/loki-config.yaml`:
```yaml
limits_config:
  retention_period: 336h  # 14 days (in hours)
```

### Adding More Logs to Monitor

Edit `promtail/promtail-config.yaml`:
```yaml
- job_name: wow_server
  static_configs:
    - targets:
        - localhost
      labels:
        job: wow_server
        __path__: /var/log/wow/{Server,DBErrors,your-new-log}.log
```

Restart Promtail: `docker compose restart promtail`

### Monitoring Additional Metrics

The `wow-exporter` is a custom Go application. To add more metrics:

1. Edit `main.go` to add new queries or metrics
2. Rebuild: `docker compose up -d --build wow-exporter`
3. Verify: `curl http://localhost:9101/metrics`

## Port Reference

| Service | Port | Purpose |
|---------|------|---------|
| Grafana | 3000 | Web UI |
| Prometheus | 9090 | Metrics API (optional) |
| Loki | 3100 | Log API (optional) |
| Node Exporter | 9100 | System metrics (internal) |
| MySQL Exporter | 9104 | Database metrics (internal) |
| WoW Exporter | 9101 | WoW server metrics (internal) |

Only Grafana (3000) needs to be accessible externally. All other ports are for inter-container communication.

## Security Notes

- The `mangos_monitor` MySQL user has **read-only** access
- Passwords are stored in `.env` (add to `.gitignore`!)
- MySQL exporter config (`.my.cnf`) contains credentials (add to `.gitignore`!)
- Consider using secrets management for production environments
- Grafana default password should be changed immediately
- Only expose Grafana port (3000) externally, keep others internal

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - see LICENSE file for details

## Acknowledgments

- [MaNGOS Project](https://getmangos.eu/)
- [Prometheus](https://prometheus.io/)
- [Grafana Labs](https://grafana.com/)