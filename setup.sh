#!/bin/bash

echo "==================================================================="
echo "  WoW MaNGOS Zero Monitoring - Interactive Setup"
echo "==================================================================="
echo ""

# Function to wait for user
wait_for_user() {
    echo ""
    read -p "Press Enter to continue..."
    echo ""
}

# Function to check if command succeeded
check_success() {
    if [ $? -eq 0 ]; then
        echo "✅ Success"
    else
        echo "❌ Failed - please fix the error above before continuing"
        exit 1
    fi
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo "⚠️  Please do not run this script as root/sudo"
    echo "   The script will ask for sudo when needed"
    exit 1
fi

echo "This script will help you set up the monitoring stack."
echo "You'll need:"
echo "  - Your MaNGOS log directory path"
echo "  - Your MaNGOS process names"
echo "  - Sudo access for setting permissions"
echo "  - MySQL/MariaDB root credentials for creating a monitoring user"
echo ""

wait_for_user

# Step 1: Create .env file
echo "==================================================================="
echo "📝 Step 1: Configuration File"
echo "==================================================================="
if [ -f .env ]; then
    echo "⚠️  .env file already exists"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing .env file"
    else
        cp .env.example .env
        echo "✅ Created new .env file"
    fi
else
    cp .env.example .env
    echo "✅ Created .env file from template"
fi

echo ""
echo "Now you need to edit the .env file with your configuration:"
echo ""
echo "  1. MANGOS_LOG_PATH - Path to your MaNGOS logs"
echo "     Example: /home/mangos/mangos/zero/bin"
echo ""
echo "  2. MANGOS_PROCESS_NAME - Your world server process"
echo "     Run: ps aux | grep mangos"
echo "     Look for the process name (usually 'mangosd')"
echo ""
echo "  3. REALM_PROCESS_NAME - Your realm server process"
echo "     (usually 'realmd')"
echo ""
read -p "Press Enter to open .env in nano editor..."
nano .env

echo ""
echo "✅ Configuration saved"
wait_for_user

# Step 2: Create data directories
echo "==================================================================="
echo "📁 Step 2: Creating Data Directories"
echo "==================================================================="
echo "Creating directories for Grafana, Prometheus, and Loki data..."

mkdir -p grafana/data prometheus/data loki/data mysql-exporter
check_success

# Step 3: Set permissions
echo ""
echo "==================================================================="
echo "🔒 Step 3: Setting Directory Permissions"
echo "==================================================================="
echo "This requires sudo access..."
echo ""

sudo chown -R 472:472 grafana/data/
check_success

sudo chown -R 10001:10001 loki/data/
check_success

sudo chown -R 65534:65534 prometheus/data/
check_success

echo "✅ Directory permissions set"
wait_for_user

# Step 4: MaNGOS log permissions
echo "==================================================================="
echo "📋 Step 4: MaNGOS Log File Permissions"
echo "==================================================================="

# Source the .env to get the path
if [ -f .env ]; then
    source .env
else
    echo "❌ .env file not found"
    exit 1
fi

if [ -z "$MANGOS_LOG_PATH" ]; then
    echo "⚠️  MANGOS_LOG_PATH not set in .env"
    echo "Please make sure you've configured .env properly"
    exit 1
fi

echo "Your MaNGOS logs are at: $MANGOS_LOG_PATH"
echo ""
echo "Promtail needs to read these log files. You have two options:"
echo ""
echo "Option 1: Make logs world-readable (easier)"
echo "  sudo chmod -R o+r $MANGOS_LOG_PATH/*.log"
echo "  sudo chmod o+rx $MANGOS_LOG_PATH"
echo ""
echo "Option 2: Run Promtail as mangos user (more secure)"
echo "  Get mangos UID: id -u mangos"
echo "  Add to docker-compose.yaml under promtail:"
echo "    user: \"<UID>:<GID>\""
echo ""
read -p "Would you like to make logs world-readable now? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    echo "Setting log permissions..."
    sudo chmod -R o+r $MANGOS_LOG_PATH/*.log 2>/dev/null
    sudo chmod o+rx $MANGOS_LOG_PATH 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Log permissions updated"
    else
        echo "⚠️  Could not set permissions - you may need to do this manually"
        echo "Run these commands:"
        echo "  sudo chmod -R o+r $MANGOS_LOG_PATH/*.log"
        echo "  sudo chmod o+rx $MANGOS_LOG_PATH"
    fi
else
    echo "⚠️  Skipped - you'll need to configure permissions manually"
fi

wait_for_user

# Step 5: MySQL Network Configuration
echo "==================================================================="
echo "🔧 Step 5: MySQL Network Configuration"
echo "==================================================================="
echo ""
echo "Docker containers need to access MySQL on the host machine."
echo "Let's verify your MySQL configuration..."
echo ""

# Check if MySQL/MariaDB is running
if ! sudo ss -tlnp | grep -q ":3306"; then
    echo "❌ MySQL/MariaDB is not running on port 3306"
    echo "   Please start MySQL before continuing"
    exit 1
fi

# Check bind address
MYSQL_BIND=$(sudo ss -tlnp | grep :3306 | awk '{print $4}' | cut -d: -f1 | head -1)

if [ "$MYSQL_BIND" = "127.0.0.1" ]; then
    echo "⚠️  WARNING: MySQL is only listening on 127.0.0.1 (localhost)"
    echo ""
    echo "Docker containers cannot reach MySQL on localhost."
    echo "You need to configure MySQL to listen on all interfaces."
    echo ""
    echo "Steps to fix:"
    echo "  1. Edit: sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf"
    echo "     (or for MySQL: sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf)"
    echo "  2. Find the [mysqld] section"
    echo "  3. Change: bind-address = 127.0.0.1"
    echo "     To:     bind-address = 0.0.0.0"
    echo "  4. Save and exit"
    echo "  5. Restart: sudo systemctl restart mariadb"
    echo ""
    read -p "Press Enter after you've fixed this, or Ctrl+C to exit..."
    echo ""
    
    # Verify the fix
    MYSQL_BIND=$(sudo ss -tlnp | grep :3306 | awk '{print $4}' | cut -d: -f1 | head -1)
    if [ "$MYSQL_BIND" = "0.0.0.0" ]; then
        echo "✅ MySQL is now listening on all interfaces"
    else
        echo "⚠️  MySQL bind address is still: $MYSQL_BIND"
        echo "   You may need to check your configuration again"
    fi
elif [ "$MYSQL_BIND" = "0.0.0.0" ] || [ "$MYSQL_BIND" = "*" ]; then
    echo "✅ MySQL is listening on all interfaces"
else
    echo "⚠️  MySQL is listening on: $MYSQL_BIND"
fi

echo ""
echo "Checking Docker network and firewall..."

# Start monitoring stack to get network info
echo "Starting Docker containers to detect network..."
docker compose up -d >/dev/null 2>&1
sleep 3

# Get Docker gateway IP
GATEWAY_IP=$(docker network inspect auto-monitor_monitoring-network 2>/dev/null | grep -oP '"Gateway": "\K[^"]+' | head -1)

if [ -n "$GATEWAY_IP" ]; then
    echo "✅ Docker gateway IP: $GATEWAY_IP"
    
    # Extract subnet (e.g., 172.22.0.1 -> 172.22.0.0/16)
    SUBNET=$(echo $GATEWAY_IP | cut -d. -f1-2).0.0/16
    echo "   Docker subnet: $SUBNET"
else
    echo "⚠️  Could not detect gateway IP"
    GATEWAY_IP="172.22.0.1"
    SUBNET="172.22.0.0/16"
    echo "   Using defaults: gateway=$GATEWAY_IP, subnet=$SUBNET"
fi

echo ""
echo "Testing Docker container network access to MySQL..."

# Simple test: can the container reach the port at all?
# We use telnet-like behavior - if we can connect to the port, network is good
if docker exec mysql-exporter sh -c "timeout 2 nc -z $GATEWAY_IP 3306" 2>/dev/null; then
    echo "✅ Docker containers can reach MySQL port 3306"
    echo "   Network and firewall configuration is correct"
else
    # nc might not be available, try a different approach
    if docker exec mysql-exporter sh -c "timeout 2 wget -q --spider telnet://$GATEWAY_IP:3306" 2>/dev/null; then
        echo "✅ Docker containers can reach MySQL port 3306"
        echo "   Network and firewall configuration is correct"
    else
        # Last resort: check if firewall rule exists and assume it works
        if sudo ufw status 2>/dev/null | grep -q "$SUBNET.*3306"; then
            echo "✅ Firewall rule exists for Docker network to access MySQL"
            echo "   Assuming network configuration is correct"
        else
            echo "⚠️  Cannot verify Docker container network access to MySQL"
            echo ""
            echo "This might be a firewall issue. Docker subnet ($SUBNET) needs access to MySQL."
            echo "Recommended firewall rule: sudo ufw allow from $SUBNET to any port 3306"
            echo ""
            read -p "Would you like to add this firewall rule now? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                sudo ufw allow from $SUBNET to any port 3306
                if [ $? -eq 0 ]; then
                    echo "✅ Firewall rule added successfully"
                else
                    echo "❌ Failed to add firewall rule"
                    echo "   You may need to add it manually"
                fi
            else
                echo "⚠️  Skipped - if MySQL monitoring doesn't work, add this rule manually"
            fi
        fi
    fi
fi

wait_for_user

# Step 6: MySQL Monitoring User Setup
echo "==================================================================="
echo "🗄️  Step 6: MySQL Monitoring User"
echo "==================================================================="
echo ""
echo "For database monitoring, we need a read-only MySQL user."
echo ""
read -p "Do you want to set up MySQL monitoring? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    echo ""
    echo "We'll create a MySQL user with these permissions:"
    echo "  - SELECT on all MaNGOS databases (read-only)"
    echo "  - PROCESS (to view active connections)"
    echo "  - REPLICATION CLIENT (for replication stats)"
    echo ""
    
    # Get MySQL root credentials
    echo "Enter your MySQL/MariaDB root credentials:"
    read -p "MySQL root username [root]: " MYSQL_ROOT_USER
    MYSQL_ROOT_USER=${MYSQL_ROOT_USER:-root}
    
    read -sp "MySQL root password: " MYSQL_ROOT_PASSWORD
    echo ""
    echo ""
    
    # Show available databases
    echo "Detecting MaNGOS databases..."
    DATABASES=$(mysql -u"$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;" 2>/dev/null | grep -E "mangos|character|realmd" | grep -v "schema")
    
    if [ -z "$DATABASES" ]; then
        echo "⚠️  Could not detect databases automatically"
        echo ""
        read -p "Enter world database name [mangos0]: " WORLD_DB
        WORLD_DB=${WORLD_DB:-mangos0}
        read -p "Enter character database name [character0]: " CHAR_DB
        CHAR_DB=${CHAR_DB:-character0}
        read -p "Enter realm database name [realmd]: " REALM_DB
        REALM_DB=${REALM_DB:-realmd}
    else
        echo "Found these databases:"
        echo "$DATABASES"
        echo ""
        read -p "Enter world database name [mangos0]: " WORLD_DB
        WORLD_DB=${WORLD_DB:-mangos0}
        read -p "Enter character database name [character0]: " CHAR_DB
        CHAR_DB=${CHAR_DB:-character0}
        read -p "Enter realm database name [realmd]: " REALM_DB
        REALM_DB=${REALM_DB:-realmd}
    fi
    
    # Generate secure password for monitoring user
    MONITOR_PASSWORD=$(openssl rand -base64 16)
    
    echo ""
    echo "Creating monitoring user 'mangos_monitor' with password: $MONITOR_PASSWORD"
    echo "(This will be saved in your configuration files)"
    echo ""
    
    # Create the SQL commands
    SQL_COMMANDS="
    -- Drop existing user if it exists (to avoid conflicts)
    DROP USER IF EXISTS 'mangos_monitor'@'localhost';
    DROP USER IF EXISTS 'mangos_monitor'@'%';
    
    -- Create monitoring user
    CREATE USER 'mangos_monitor'@'localhost' IDENTIFIED BY '$MONITOR_PASSWORD';
    CREATE USER 'mangos_monitor'@'%' IDENTIFIED BY '$MONITOR_PASSWORD';
    
    -- Grant read-only permissions on all three databases
    GRANT SELECT ON $WORLD_DB.* TO 'mangos_monitor'@'localhost';
    GRANT SELECT ON $CHAR_DB.* TO 'mangos_monitor'@'localhost';
    GRANT SELECT ON $REALM_DB.* TO 'mangos_monitor'@'localhost';
    GRANT SELECT ON $WORLD_DB.* TO 'mangos_monitor'@'%';
    GRANT SELECT ON $CHAR_DB.* TO 'mangos_monitor'@'%';
    GRANT SELECT ON $REALM_DB.* TO 'mangos_monitor'@'%';
    
    -- Grant process and replication permissions
    GRANT PROCESS ON *.* TO 'mangos_monitor'@'localhost';
    GRANT PROCESS ON *.* TO 'mangos_monitor'@'%';
    GRANT REPLICATION CLIENT ON *.* TO 'mangos_monitor'@'localhost';
    GRANT REPLICATION CLIENT ON *.* TO 'mangos_monitor'@'%';
    
    -- Apply changes
    FLUSH PRIVILEGES;
    
    -- Verify user was created
    SELECT User, Host FROM mysql.user WHERE User = 'mangos_monitor';
    "
    
    # Save to temp file
    echo "$SQL_COMMANDS" > /tmp/mangos_monitor_setup.sql
    
    # Execute SQL
    echo "Executing SQL commands..."
    mysql -u"$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" < /tmp/mangos_monitor_setup.sql 2>/tmp/mysql_error.log
    
    if [ $? -eq 0 ]; then
        echo "✅ MySQL monitoring user created successfully"
        
        # Update .env file with MySQL settings
        echo ""
        echo "Updating .env file with MySQL credentials..."
        
        # Check if MySQL variables exist in .env, if not append them
        if ! grep -q "^MYSQL_HOST=" .env 2>/dev/null; then
            echo "" >> .env
            echo "# MySQL Database Configuration" >> .env
            echo "MYSQL_HOST=localhost" >> .env
            echo "MYSQL_PORT=3306" >> .env
            echo "MYSQL_WORLD_DB=$WORLD_DB" >> .env
            echo "MYSQL_CHAR_DB=$CHAR_DB" >> .env
            echo "MYSQL_REALM_DB=$REALM_DB" >> .env
            echo "MYSQL_USER=mangos_monitor" >> .env
            echo "MYSQL_PASSWORD=$MONITOR_PASSWORD" >> .env
        else
            # Update existing values
            sed -i "s|^MYSQL_HOST=.*|MYSQL_HOST=localhost|" .env
            sed -i "s|^MYSQL_PORT=.*|MYSQL_PORT=3306|" .env
            sed -i "s|^MYSQL_WORLD_DB=.*|MYSQL_WORLD_DB=$WORLD_DB|" .env
            sed -i "s|^MYSQL_CHAR_DB=.*|MYSQL_CHAR_DB=$CHAR_DB|" .env
            sed -i "s|^MYSQL_REALM_DB=.*|MYSQL_REALM_DB=$REALM_DB|" .env
            sed -i "s|^MYSQL_USER=.*|MYSQL_USER=mangos_monitor|" .env
            sed -i "s|^MYSQL_PASSWORD=.*|MYSQL_PASSWORD=$MONITOR_PASSWORD|" .env
        fi
        
        echo "✅ .env file updated"

        # Create MySQL exporter configuration with gateway IP
        echo ""
        echo "Creating MySQL exporter configuration..."
        
        cat > mysql-exporter/.my.cnf << EOF
[client]
user=mangos_monitor
password=$MONITOR_PASSWORD
host=$GATEWAY_IP
port=3306
protocol=tcp
EOF
        
        chmod 600 mysql-exporter/.my.cnf
        echo "✅ MySQL exporter config created (using gateway IP: $GATEWAY_IP)"
        
        # Test connection from Docker container
        echo ""
        echo "Testing MySQL connection from Docker container..."
        
        if docker exec mysql-exporter mysql --defaults-file=/etc/.my.cnf -e "SELECT 1;" &>/dev/null; then
            echo "✅ Docker container can connect to MySQL"
        else
            echo "⚠️  Docker container cannot connect to MySQL"
            echo "   This might be a network or firewall issue"
            echo "   Check the troubleshooting section in README.md"
        fi
        
        # Test connection to all three databases
        echo ""
        echo "Testing database access..."
        
        echo -n "  World database ($WORLD_DB)... "
        if mysql -u"mangos_monitor" -p"$MONITOR_PASSWORD" -h"$GATEWAY_IP" -e "SELECT 1 FROM $WORLD_DB.item_template LIMIT 1;" &>/dev/null; then
            echo "✅"
        else
            echo "❌"
        fi
        
        echo -n "  Character database ($CHAR_DB)... "
        if mysql -u"mangos_monitor" -p"$MONITOR_PASSWORD" -h"$GATEWAY_IP" -e "SELECT COUNT(*) FROM $CHAR_DB.characters;" &>/dev/null; then
            echo "✅"
        else
            echo "❌"
        fi
        
        echo -n "  Realm database ($REALM_DB)... "
        if mysql -u"mangos_monitor" -p"$MONITOR_PASSWORD" -h"$GATEWAY_IP" -e "SELECT COUNT(*) FROM $REALM_DB.account;" &>/dev/null; then
            echo "✅"
        else
            echo "❌"
        fi
        
    else
        echo "❌ Failed to create MySQL user"
        echo "Error details:"
        cat /tmp/mysql_error.log
        echo ""
        echo "You can create the user manually with these commands:"
        echo ""
        cat /tmp/mangos_monitor_setup.sql
        echo ""
    fi
    
    # Clean up temp files
    rm -f /tmp/mangos_monitor_setup.sql /tmp/mysql_error.log
    
else
    echo "⚠️  Skipped MySQL setup"
    echo "   You can set this up later by running these SQL commands:"
    echo ""
    echo "   CREATE USER 'mangos_monitor'@'localhost' IDENTIFIED BY 'your_password';"
    echo "   GRANT SELECT ON mangos0.* TO 'mangos_monitor'@'localhost';"
    echo "   GRANT SELECT ON character0.* TO 'mangos_monitor'@'localhost';"
    echo "   GRANT SELECT ON realmd.* TO 'mangos_monitor'@'localhost';"
    echo "   GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'mangos_monitor'@'localhost';"
    echo "   FLUSH PRIVILEGES;"
    echo ""
fi

wait_for_user

# Step 7: Verify configuration
echo "==================================================================="
echo "🔍 Step 7: Verifying Setup"
echo "==================================================================="

echo "Checking if MaNGOS logs exist..."
if [ -d "$MANGOS_LOG_PATH" ]; then
    LOG_COUNT=$(ls -1 $MANGOS_LOG_PATH/*.log 2>/dev/null | wc -l)
    if [ $LOG_COUNT -gt 0 ]; then
        echo "✅ Found $LOG_COUNT log files"
        
        # Check ownership and permissions
        FIRST_LOG=$(ls -1 $MANGOS_LOG_PATH/*.log 2>/dev/null | head -1)
        LOG_OWNER=$(stat -c '%U' "$FIRST_LOG" 2>/dev/null)
        LOG_GROUP=$(stat -c '%G' "$FIRST_LOG" 2>/dev/null)
        LOG_PERMS=$(stat -c '%a' "$FIRST_LOG" 2>/dev/null)
        CURRENT_USER=$(whoami)
        
        echo "   Log owner: $LOG_OWNER:$LOG_GROUP"
        echo "   Permissions: $LOG_PERMS"
        echo "   Current user: $CURRENT_USER"
        
        # Check if current user can read the logs
        if [ -r "$FIRST_LOG" ]; then
            echo "   ✅ Current user can read log files"
        else
            echo "   ⚠️  Current user cannot read log files"
            echo ""
            echo "   Promtail runs as root in Docker and should be able to read them,"
            echo "   but you may have issues if you need to access them manually."
            echo ""
            echo "   To allow all users to read: sudo chmod -R o+r $MANGOS_LOG_PATH/*.log"
        fi
        
        # Warn if logs are owned by a different user
        if [ "$LOG_OWNER" != "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
            echo ""
            echo "   ℹ️  Note: Logs are owned by '$LOG_OWNER', you're running as '$CURRENT_USER'"
            echo "   This is fine - Promtail container runs as root and can read them."
        fi
    else
        echo "⚠️  No .log files found in $MANGOS_LOG_PATH"
    fi
else
    echo "❌ Directory $MANGOS_LOG_PATH does not exist"
    echo "   Please check your MANGOS_LOG_PATH in .env"
    echo ""
    echo "   Common paths:"
    echo "   - /home/mangos/mangos/zero/bin"
    echo "   - /opt/mangos/bin"
    echo ""
    read -p "   Enter the correct path or press Enter to continue: " NEW_PATH
    if [ -n "$NEW_PATH" ] && [ -d "$NEW_PATH" ]; then
        sed -i "s|^MANGOS_LOG_PATH=.*|MANGOS_LOG_PATH=$NEW_PATH|" .env
        echo "   ✅ Updated MANGOS_LOG_PATH in .env"
        source .env
    fi
fi

echo ""
echo "Checking if MaNGOS processes are running..."
if [ -n "$MANGOS_PROCESS_NAME" ]; then
    if pgrep -x "$MANGOS_PROCESS_NAME" > /dev/null; then
        echo "✅ $MANGOS_PROCESS_NAME is running"
    else
        echo "⚠️  $MANGOS_PROCESS_NAME is not running"
        echo "   This is OK if your server is currently stopped"
    fi
fi

if [ -n "$REALM_PROCESS_NAME" ]; then
    if pgrep -x "$REALM_PROCESS_NAME" > /dev/null; then
        echo "✅ $REALM_PROCESS_NAME is running"
    else
        echo "⚠️  $REALM_PROCESS_NAME is not running"
        echo "   This is OK if your server is currently stopped"
    fi
fi

wait_for_user

# Final summary
echo "==================================================================="
echo "  Setup Complete!"
echo "==================================================================="
echo ""
echo "Next steps:"
echo ""
echo "  1. Restart the monitoring stack with updated configuration:"
echo "     docker compose down"
echo "     docker compose up -d"
echo ""
echo "  2. Check container status:"
echo "     docker compose ps"
echo ""
echo "  3. View logs if there are issues:"
echo "     docker compose logs mysql-exporter"
echo "     docker compose logs prometheus"
echo ""
echo "  4. Access Grafana:"
echo "     http://localhost:3000"
echo "     Default login: admin/admin"
echo "==================================================================="