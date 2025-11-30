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
echo "  - Creating a read only MySQL user for metric gathering"
echo ""

wait_for_user

# Step 1: Create .env file
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
echo "📁 Step 2: Creating Data Directories"
echo "==================================================================="
echo "Creating directories for Grafana, Prometheus, and Loki data..."

mkdir -p grafana/data prometheus/data loki/data
check_success

# Step 3: Set permissions
echo ""
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

# Step 5: MySQL Monitoring User Setup
echo "🗄️  Step 5: MySQL Monitoring User"
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
    echo "Enter your MySQL root credentials (or admin user with GRANT privileges):"
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
    echo "(This will be saved in your .env file)"
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

                # Create MySQL exporter configuration
        echo ""
        echo "Creating MySQL exporter configuration..."
        mkdir -p mysql-exporter
        
        cat > mysql-exporter/.my.cnf << EOF
[client]
user=mangos_monitor
password=$MONITOR_PASSWORD
host=$MYSQL_HOST
port=3306
EOF
        
        chmod 600 mysql-exporter/.my.cnf
        echo "✅ MySQL exporter config created"
        
        # Test connection on all three databases
        echo ""
        echo "Testing connections..."
        
        echo -n "  World database ($WORLD_DB)... "
        if mysql -u"mangos_monitor" -p"$MONITOR_PASSWORD" -e "SELECT 1 FROM $WORLD_DB.item_template LIMIT 1;" &>/dev/null; then
            echo "✅"
        else
            echo "❌"
        fi
        
        echo -n "  Character database ($CHAR_DB)... "
        if mysql -u"mangos_monitor" -p"$MONITOR_PASSWORD" -e "SELECT COUNT(*) FROM $CHAR_DB.characters;" &>/dev/null; then
            echo "✅"
        else
            echo "❌"
        fi
        
        echo -n "  Realm database ($REALM_DB)... "
        if mysql -u"mangos_monitor" -p"$MONITOR_PASSWORD" -e "SELECT COUNT(*) FROM $REALM_DB.account;" &>/dev/null; then
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

# Step 6: Verify configuration
echo "🔍 Step 6: Verifying Setup"
echo "==================================================================="

echo "Checking if MaNGOS logs exist..."
if [ -d "$MANGOS_LOG_PATH" ]; then
    LOG_COUNT=$(ls -1 $MANGOS_LOG_PATH/*.log 2>/dev/null | wc -l)
    if [ $LOG_COUNT -gt 0 ]; then
        echo "✅ Found $LOG_COUNT log files"
    else
        echo "⚠️  No .log files found in $MANGOS_LOG_PATH"
    fi
else
    echo "❌ Directory $MANGOS_LOG_PATH does not exist"
    echo "   Please check your MANGOS_LOG_PATH in .env"
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
echo "  1. Review your configuration:"
echo "     cat .env"
echo ""
echo "  2. Start the monitoring stack:"
echo "     docker compose up -d"
echo ""
echo "  3. Check container status:"
echo "     docker compose ps"
echo ""
echo "  4. View logs if there are issues:"
echo "     docker compose logs -f"
echo ""
echo "  5. Access Grafana:"
echo "     http://localhost:3000"
echo "     Default login: admin/admin"
echo ""
echo "For Traefik integration, see the README.md"
echo ""
echo "==================================================================="