#!/bin/bash

#############################################################################
# Nextcloud Server Installation Script
# Author: System Administrator
# Description: Automated installation of latest Nextcloud with separated
#              file storage and IP address management
# Compatible: Ubuntu 20.04+, Debian 11+
# Version: 1.0
#############################################################################

set -e  # Exit on error
set -o pipefail  # Exit on pipe failure

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_VERSION="1.0"
NEXTCLOUD_URL="https://download.nextcloud.com/server/releases/latest.tar.bz2"
MIN_PHP_VERSION="8.1"
SUPPORTED_OS=("ubuntu" "debian")
LOG_FILE="/var/log/nextcloud_install_$(date +%Y%m%d_%H%M%S).log"

# Global variables (will be set during installation)
DB_TYPE=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
DB_ROOT_PASSWORD=""
NC_DATA_DIR=""
NC_ADMIN_USER=""
NC_ADMIN_PASSWORD=""
NC_DOMAIN=""
WEB_SERVER=""
PHP_VERSION=""
NC_PATH="/var/www/nextcloud"
USE_SSL=""
EMAIL=""

#############################################################################
# Helper Functions
#############################################################################

print_message() {
    local type=$1
    shift
    local message="$*"
    
    case $type in
        "error")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "success")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "warning")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "info")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "$message" | tee -a "$LOG_FILE"
            ;;
    esac
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_message "error" "This script must be run as root or with sudo privileges"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        OS_VERSION="$VERSION_ID"
        
        if [[ ! " ${SUPPORTED_OS[@]} " =~ " ${OS} " ]]; then
            print_message "error" "Unsupported OS: $OS"
            print_message "info" "Supported OS: ${SUPPORTED_OS[*]}"
            exit 1
        fi
        
        print_message "success" "Detected OS: $OS $OS_VERSION"
    else
        print_message "error" "Cannot detect OS"
        exit 1
    fi
}

check_internet() {
    print_message "info" "Checking internet connectivity..."
    
    if ping -c 1 download.nextcloud.com &> /dev/null; then
        print_message "success" "Internet connection verified"
    else
        print_message "error" "No internet connection detected"
        exit 1
    fi
}

detect_php_version() {
    # Check for existing PHP or get available versions
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
        print_message "info" "Detected PHP version: $PHP_VERSION"
    else
        # Get latest available PHP version
        apt-get update &> /dev/null
        PHP_VERSION=$(apt-cache search "^php[0-9]\.[0-9]-fpm$" | grep -oP "php\K[0-9]\.[0-9]" | sort -V | tail -1)
        
        if [[ -z "$PHP_VERSION" ]]; then
            PHP_VERSION="8.2"  # Default fallback
        fi
        print_message "info" "Will install PHP version: $PHP_VERSION"
    fi
}

check_existing_installation() {
    if [[ -d "$NC_PATH" ]]; then
        print_message "warning" "Existing Nextcloud installation detected at $NC_PATH"
        read -p "Do you want to continue and overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "info" "Installation aborted by user"
            exit 0
        fi
        
        # Backup existing installation
        backup_dir="/var/backups/nextcloud_$(date +%Y%m%d_%H%M%S)"
        print_message "info" "Backing up existing installation to $backup_dir"
        mkdir -p "$backup_dir"
        cp -R "$NC_PATH" "$backup_dir/"
        
        # Backup database if config exists
        if [[ -f "$NC_PATH/config/config.php" ]]; then
            db_name=$(grep "'dbname'" "$NC_PATH/config/config.php" | cut -d "'" -f 4)
            if [[ -n "$db_name" ]]; then
                mysqldump "$db_name" > "$backup_dir/database.sql" 2>/dev/null || true
            fi
        fi
    fi
}

secure_password_prompt() {
    local prompt=$1
    local var_name=$2
    local password=""
    local password_confirm=""
    
    while true; do
        read -s -p "$prompt: " password
        echo
        read -s -p "Confirm $prompt: " password_confirm
        echo
        
        if [[ "$password" != "$password_confirm" ]]; then
            print_message "error" "Passwords do not match. Please try again."
        elif [[ "${#password}" -lt 8 ]]; then
            print_message "error" "Password must be at least 8 characters long."
        else
            eval "$var_name='$password'"
            break
        fi
    done
}

generate_random_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

#############################################################################
# Configuration Collection
#############################################################################

collect_configuration() {
    print_message "info" "Starting configuration collection..."
    
    # Web server selection
    echo
    print_message "info" "Select web server:"
    echo "1) Apache"
    echo "2) Nginx"
    read -p "Enter choice [1-2]: " -n 1 -r
    echo
    
    case $REPLY in
        1) WEB_SERVER="apache" ;;
        2) WEB_SERVER="nginx" ;;
        *) print_message "error" "Invalid choice"; exit 1 ;;
    esac
    
    # Database type selection
    echo
    print_message "info" "Select database type:"
    echo "1) MariaDB (Recommended)"
    echo "2) MySQL"
    read -p "Enter choice [1-2]: " -n 1 -r
    echo
    
    case $REPLY in
        1) DB_TYPE="mariadb" ;;
        2) DB_TYPE="mysql" ;;
        *) print_message "error" "Invalid choice"; exit 1 ;;
    esac
    
    # Database configuration
    echo
    print_message "info" "Database Configuration"
    
    # Check for existing database installation
    local existing_db=""
    if systemctl is-active --quiet mariadb 2>/dev/null; then
        existing_db="MariaDB"
        print_message "info" "Detected existing MariaDB installation"
    elif systemctl is-active --quiet mysql 2>/dev/null; then
        existing_db="MySQL"
        print_message "info" "Detected existing MySQL installation"
    fi
    
    if [[ -n "$existing_db" ]]; then
        print_message "warning" "Existing $existing_db installation detected"
        print_message "info" "Make sure you know the root password for the existing database"
    fi
    
    read -p "Database name [nextcloud]: " DB_NAME
    DB_NAME=${DB_NAME:-nextcloud}
    
    read -p "Database user [nextcloud]: " DB_USER
    DB_USER=${DB_USER:-nextcloud}
    
    secure_password_prompt "Database password" DB_PASSWORD
    
    if [[ -n "$existing_db" ]]; then
        print_message "info" "Enter the EXISTING root password for $existing_db"
    fi
    secure_password_prompt "Database root password" DB_ROOT_PASSWORD
    
    # Data directory
    echo
    print_message "info" "File Storage Configuration"
    print_message "info" "This directory will store all user files separately from Nextcloud installation"
    
    read -p "Enter data directory path [/mnt/nextcloud-data]: " NC_DATA_DIR
    NC_DATA_DIR=${NC_DATA_DIR:-/mnt/nextcloud-data}
    
    # Create data directory if it doesn't exist
    if [[ ! -d "$NC_DATA_DIR" ]]; then
        print_message "info" "Creating data directory: $NC_DATA_DIR"
        mkdir -p "$NC_DATA_DIR"
    fi
    
    # Nextcloud admin configuration
    echo
    print_message "info" "Nextcloud Administrator Configuration"
    
    read -p "Admin username [admin]: " NC_ADMIN_USER
    NC_ADMIN_USER=${NC_ADMIN_USER:-admin}
    
    secure_password_prompt "Admin password" NC_ADMIN_PASSWORD
    
    # Domain/IP configuration
    echo
    print_message "info" "Domain/Access Configuration"
    print_message "info" "Enter your domain name or IP address for accessing Nextcloud"
    
    read -p "Domain/IP address: " NC_DOMAIN
    
    while [[ -z "$NC_DOMAIN" ]]; do
        print_message "error" "Domain/IP cannot be empty"
        read -p "Domain/IP address: " NC_DOMAIN
    done
    
    # SSL configuration
    echo
    read -p "Do you want to configure SSL/HTTPS? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        USE_SSL="yes"
        read -p "Enter email for Let's Encrypt (or press Enter to skip): " EMAIL
    fi
    
    # Summary
    echo
    print_message "info" "Configuration Summary:"
    echo "----------------------------------------"
    echo "Web Server:        $WEB_SERVER"
    echo "Database Type:     $DB_TYPE"
    echo "Database Name:     $DB_NAME"
    echo "Database User:     $DB_USER"
    echo "Data Directory:    $NC_DATA_DIR"
    echo "Admin User:        $NC_ADMIN_USER"
    echo "Domain/IP:         $NC_DOMAIN"
    echo "SSL Enabled:       ${USE_SSL:-no}"
    echo "----------------------------------------"
    
    read -p "Proceed with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "info" "Installation cancelled"
        exit 0
    fi
}

#############################################################################
# Installation Functions
#############################################################################

install_dependencies() {
    print_message "info" "Installing system dependencies..."
    
    # Update package lists
    apt-get update
    
    # Common packages
    local common_packages="wget curl sudo cron bzip2 rsync openssl"
    
    # PHP packages
    local php_packages="php${PHP_VERSION} php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql php${PHP_VERSION}-pgsql \
                        php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
                        php${PHP_VERSION}-mbstring php${PHP_VERSION}-gd php${PHP_VERSION}-curl \
                        php${PHP_VERSION}-intl php${PHP_VERSION}-bcmath php${PHP_VERSION}-gmp \
                        php${PHP_VERSION}-imagick php${PHP_VERSION}-redis php${PHP_VERSION}-apcu \
                        php${PHP_VERSION}-opcache"
    
    # Web server specific packages
    if [[ "$WEB_SERVER" == "apache" ]]; then
        local web_packages="apache2 libapache2-mod-php${PHP_VERSION}"
    else
        local web_packages="nginx"
    fi
    
    # Database packages
    if [[ "$DB_TYPE" == "mariadb" ]]; then
        local db_packages="mariadb-server mariadb-client"
    else
        local db_packages="mysql-server mysql-client"
    fi
    
    # Additional packages
    local additional_packages="redis-server imagemagick ffmpeg"
    
    # Install all packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        $common_packages \
        $php_packages \
        $web_packages \
        $db_packages \
        $additional_packages \
        2>&1 | tee -a "$LOG_FILE"
    
    print_message "success" "Dependencies installed successfully"
}

configure_database() {
    print_message "info" "Configuring database..."
    
    # Start database service
    if [[ "$DB_TYPE" == "mariadb" ]]; then
        systemctl start mariadb
        systemctl enable mariadb
    else
        systemctl start mysql
        systemctl enable mysql
    fi
    
    # Secure installation - Using modern MySQL/MariaDB commands
    print_message "info" "Securing database installation..."
    
    # Check if we can connect without password (fresh installation)
    if mysql -u root -e "SELECT 1" &>/dev/null; then
        print_message "info" "Setting up fresh database installation..."
        
        # Set root password using ALTER USER for MySQL 5.7+ / MariaDB 10.4+
        mysql <<EOF
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Remove remote root access
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Reload privilege tables
FLUSH PRIVILEGES;
EOF
    else
        # Try to connect with the provided root password
        if mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1" &>/dev/null; then
            print_message "info" "Using existing database root password..."
        else
            print_message "error" "Cannot connect to database. Please check root password."
            print_message "info" "If MySQL/MariaDB is already installed, make sure the root password you entered is correct."
            exit 1
        fi
    fi
    
    # Create Nextcloud database and user
    print_message "info" "Creating Nextcloud database and user..."
    mysql -u root -p"$DB_ROOT_PASSWORD" <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Configure MariaDB/MySQL for Nextcloud
    cat > /etc/mysql/conf.d/nextcloud.cnf <<EOF
[mysqld]
transaction_isolation = READ-COMMITTED
binlog_format = ROW
innodb_large_prefix=ON
innodb_file_format=Barracuda
innodb_file_per_table=ON
innodb_buffer_pool_size = 128M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
skip-name-resolve
EOF
    
    # Restart database service
    if [[ "$DB_TYPE" == "mariadb" ]]; then
        systemctl restart mariadb
    else
        systemctl restart mysql
    fi
    
    print_message "success" "Database configured successfully"
}

download_nextcloud() {
    print_message "info" "Downloading latest Nextcloud..."
    
    cd /tmp
    
    # Download latest Nextcloud
    wget -q "$NEXTCLOUD_URL" -O nextcloud-latest.tar.bz2
    
    # Verify download
    if [[ ! -f nextcloud-latest.tar.bz2 ]]; then
        print_message "error" "Failed to download Nextcloud"
        exit 1
    fi
    
    # Extract Nextcloud
    print_message "info" "Extracting Nextcloud..."
    tar -xjf nextcloud-latest.tar.bz2
    
    # Move to web directory
    if [[ -d "$NC_PATH" ]]; then
        rm -rf "$NC_PATH"
    fi
    mv nextcloud "$NC_PATH"
    
    # Clean up
    rm -f nextcloud-latest.tar.bz2
    
    print_message "success" "Nextcloud downloaded and extracted"
}

configure_apache() {
    print_message "info" "Configuring Apache..."
    
    # Enable required modules
    a2enmod rewrite headers env dir mime setenvif ssl
    
    # Create Nextcloud site configuration
    cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
    ServerName $NC_DOMAIN
    DocumentRoot $NC_PATH
    
    <Directory $NC_PATH>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        
        SetEnv HOME $NC_PATH
        SetEnv HTTP_HOME $NC_PATH
    </Directory>
    
    <Directory $NC_DATA_DIR>
        Require all denied
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF
    
    # Enable site
    a2ensite nextcloud.conf
    a2dissite 000-default.conf
    
    # Configure PHP
    configure_php_apache
    
    # Restart Apache
    systemctl restart apache2
    systemctl enable apache2
    
    print_message "success" "Apache configured successfully"
}

configure_nginx() {
    print_message "info" "Configuring Nginx..."
    
    # Create Nextcloud site configuration
    cat > /etc/nginx/sites-available/nextcloud <<'EOF'
upstream php-handler {
    server unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${NC_DOMAIN};
    
    # Path to Nextcloud
    root ${NC_PATH};
    
    # Max upload size
    client_max_body_size 512M;
    fastcgi_buffers 64 4K;
    
    # Enable gzip
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json application/xml;
    
    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag "noindex, nofollow";
    add_header X-Download-Options noopen;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Permitted-Cross-Domain-Policies none;
    add_header Referrer-Policy no-referrer;
    
    # Remove X-Powered-By
    fastcgi_hide_header X-Powered-By;
    
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }
    
    location = /.well-known/carddav {
        return 301 $scheme://$host:$server_port/remote.php/dav;
    }
    
    location = /.well-known/caldav {
        return 301 $scheme://$host:$server_port/remote.php/dav;
    }
    
    location / {
        rewrite ^ /index.php;
    }
    
    location ~ ^\/(?:build|tests|config|lib|3rdparty|templates|data)\/ {
        deny all;
    }
    
    location ~ ^\/(?:\.|autotest|occ|issue|indie|db_|console) {
        deny all;
    }
    
    location ~ ^\/(?:index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+)\.php(?:$|\/) {
        fastcgi_split_path_info ^(.+?\.php)(\/.*|)$;
        set $path_info $fastcgi_path_info;
        try_files $fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $path_info;
        fastcgi_param HTTPS off;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }
    
    location ~ ^\/(?:updater|oc[ms]-provider)(?:$|\/) {
        try_files $uri/ =404;
        index index.php;
    }
    
    location ~ \.(?:css|js|woff2?|svg|gif|map)$ {
        try_files $uri /index.php$request_uri;
        add_header Cache-Control "public, max-age=15778463";
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header X-Robots-Tag "noindex, nofollow";
        add_header X-Download-Options noopen;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Permitted-Cross-Domain-Policies none;
        add_header Referrer-Policy no-referrer;
        access_log off;
    }
    
    location ~ \.(?:png|html|ttf|ico|jpg|jpeg|bcmap)$ {
        try_files $uri /index.php$request_uri;
        access_log off;
    }
}
EOF
    
    # Replace variables in config
    sed -i "s|\${PHP_VERSION}|$PHP_VERSION|g" /etc/nginx/sites-available/nextcloud
    sed -i "s|\${NC_DOMAIN}|$NC_DOMAIN|g" /etc/nginx/sites-available/nextcloud
    sed -i "s|\${NC_PATH}|$NC_PATH|g" /etc/nginx/sites-available/nextcloud
    
    # Enable site
    ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Configure PHP-FPM
    configure_php_fpm
    
    # Test and restart Nginx
    nginx -t
    systemctl restart nginx
    systemctl enable nginx
    systemctl restart php${PHP_VERSION}-fpm
    systemctl enable php${PHP_VERSION}-fpm
    
    print_message "success" "Nginx configured successfully"
}

configure_php_apache() {
    print_message "info" "Configuring PHP for Apache..."
    
    local php_ini="/etc/php/$PHP_VERSION/apache2/php.ini"
    
    # Configure PHP settings
    sed -i 's/memory_limit = .*/memory_limit = 512M/' "$php_ini"
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 512M/' "$php_ini"
    sed -i 's/post_max_size = .*/post_max_size = 512M/' "$php_ini"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$php_ini"
    sed -i 's/max_input_time = .*/max_input_time = 300/' "$php_ini"
    
    # Enable OPcache
    sed -i 's/;opcache.enable=.*/opcache.enable=1/' "$php_ini"
    sed -i 's/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=8/' "$php_ini"
    sed -i 's/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' "$php_ini"
    sed -i 's/;opcache.memory_consumption=.*/opcache.memory_consumption=128/' "$php_ini"
    sed -i 's/;opcache.save_comments=.*/opcache.save_comments=1/' "$php_ini"
    sed -i 's/;opcache.revalidate_freq=.*/opcache.revalidate_freq=1/' "$php_ini"
}

configure_php_fpm() {
    print_message "info" "Configuring PHP-FPM..."
    
    local php_ini="/etc/php/$PHP_VERSION/fpm/php.ini"
    local php_pool="/etc/php/$PHP_VERSION/fpm/pool.d/www.conf"
    
    # Configure PHP settings
    sed -i 's/memory_limit = .*/memory_limit = 512M/' "$php_ini"
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 512M/' "$php_ini"
    sed -i 's/post_max_size = .*/post_max_size = 512M/' "$php_ini"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$php_ini"
    sed -i 's/max_input_time = .*/max_input_time = 300/' "$php_ini"
    
    # Enable OPcache
    sed -i 's/;opcache.enable=.*/opcache.enable=1/' "$php_ini"
    sed -i 's/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=8/' "$php_ini"
    sed -i 's/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' "$php_ini"
    sed -i 's/;opcache.memory_consumption=.*/opcache.memory_consumption=128/' "$php_ini"
    sed -i 's/;opcache.save_comments=.*/opcache.save_comments=1/' "$php_ini"
    sed -i 's/;opcache.revalidate_freq=.*/opcache.revalidate_freq=1/' "$php_ini"
    
    # Configure PHP-FPM pool
    sed -i 's/pm.max_children = .*/pm.max_children = 50/' "$php_pool"
    sed -i 's/pm.start_servers = .*/pm.start_servers = 5/' "$php_pool"
    sed -i 's/pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "$php_pool"
    sed -i 's/pm.max_spare_servers = .*/pm.max_spare_servers = 35/' "$php_pool"
    
    # Clear OPcache on restart
    sed -i 's/;clear_env = no/clear_env = no/' "$php_pool"
    
    # Add environment variables
    cat >> "$php_pool" <<EOF

; Nextcloud environment variables
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
EOF
}

configure_redis() {
    print_message "info" "Configuring Redis cache..."
    
    # Configure Redis
    sed -i "s/^# unixsocket /unixsocket /" /etc/redis/redis.conf
    sed -i "s/^# unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf
    sed -i "s/^port 6379/port 0/" /etc/redis/redis.conf
    
    # Add www-data to redis group
    usermod -a -G redis www-data
    
    # Restart Redis
    systemctl restart redis-server
    systemctl enable redis-server
    
    print_message "success" "Redis configured successfully"
}

set_permissions() {
    print_message "info" "Setting file permissions..."
    
    # Set ownership
    chown -R www-data:www-data "$NC_PATH"
    chown -R www-data:www-data "$NC_DATA_DIR"
    
    # Set permissions for Nextcloud
    find "$NC_PATH" -type d -exec chmod 755 {} \;
    find "$NC_PATH" -type f -exec chmod 644 {} \;
    
    # Set permissions for data directory
    chmod 770 "$NC_DATA_DIR"
    
    print_message "success" "Permissions set successfully"
}

install_nextcloud() {
    print_message "info" "Installing Nextcloud..."
    
    cd "$NC_PATH"
    
    # Run Nextcloud installer
    sudo -u www-data php occ maintenance:install \
        --database="mysql" \
        --database-name="$DB_NAME" \
        --database-user="$DB_USER" \
        --database-pass="$DB_PASSWORD" \
        --admin-user="$NC_ADMIN_USER" \
        --admin-pass="$NC_ADMIN_PASSWORD" \
        --data-dir="$NC_DATA_DIR"
    
    # Configure trusted domains
    sudo -u www-data php occ config:system:set trusted_domains 0 --value="localhost"
    sudo -u www-data php occ config:system:set trusted_domains 1 --value="$NC_DOMAIN"
    sudo -u www-data php occ config:system:set trusted_domains 2 --value="$(hostname -I | awk '{print $1}')"
    
    # Configure Redis cache
    sudo -u www-data php occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu"
    sudo -u www-data php occ config:system:set memcache.distributed --value="\\OC\\Memcache\\Redis"
    sudo -u www-data php occ config:system:set memcache.locking --value="\\OC\\Memcache\\Redis"
    sudo -u www-data php occ config:system:set redis host --value="/var/run/redis/redis-server.sock"
    sudo -u www-data php occ config:system:set redis port --value=0
    
    # Set default phone region
    sudo -u www-data php occ config:system:set default_phone_region --value="US"
    
    # Configure background jobs
    sudo -u www-data php occ background:cron
    
    print_message "success" "Nextcloud installed successfully"
}

configure_cron() {
    print_message "info" "Configuring cron jobs..."
    
    # Add Nextcloud cron job
    echo "*/5 * * * * sudo -u www-data php $NC_PATH/occ cron:run" > /etc/cron.d/nextcloud
    
    # Set permissions
    chmod 644 /etc/cron.d/nextcloud
    
    print_message "success" "Cron jobs configured"
}

configure_ssl() {
    if [[ "$USE_SSL" != "yes" ]]; then
        return
    fi
    
    print_message "info" "Configuring SSL certificate..."
    
    # Install certbot
    if [[ "$WEB_SERVER" == "apache" ]]; then
        apt-get install -y certbot python3-certbot-apache
        
        if [[ -n "$EMAIL" ]]; then
            certbot --apache --non-interactive --agree-tos --email "$EMAIL" -d "$NC_DOMAIN"
        else
            certbot --apache --non-interactive --agree-tos --register-unsafely-without-email -d "$NC_DOMAIN"
        fi
    else
        apt-get install -y certbot python3-certbot-nginx
        
        if [[ -n "$EMAIL" ]]; then
            certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$NC_DOMAIN"
        else
            certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d "$NC_DOMAIN"
        fi
    fi
    
    # Add auto-renewal cron job
    echo "0 2 * * * /usr/bin/certbot renew --quiet" >> /etc/crontab
    
    print_message "success" "SSL certificate configured"
}

create_helper_scripts() {
    print_message "info" "Creating helper scripts..."
    
    # Create IP management script
    cat > /usr/local/bin/nextcloud-add-ip <<'SCRIPT_EOF'
#!/bin/bash

NC_PATH="/var/www/nextcloud"
CONFIG_FILE="$NC_PATH/config/config.php"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <IP_ADDRESS|DOMAIN>"
    echo "Example: $0 192.168.1.100"
    echo "Example: $0 cloud.example.com"
    exit 1
fi

NEW_DOMAIN=$1

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Get current trusted domains count
LAST_INDEX=$(sudo -u www-data php "$NC_PATH/occ" config:system:get trusted_domains | tail -1 | grep -oE '^[0-9]+')

if [[ -z "$LAST_INDEX" ]]; then
    LAST_INDEX=0
else
    LAST_INDEX=$((LAST_INDEX + 1))
fi

# Add new trusted domain
sudo -u www-data php "$NC_PATH/occ" config:system:set trusted_domains $LAST_INDEX --value="$NEW_DOMAIN"

echo "Successfully added '$NEW_DOMAIN' to trusted domains (index: $LAST_INDEX)"
echo ""
echo "Current trusted domains:"
sudo -u www-data php "$NC_PATH/occ" config:system:get trusted_domains

SCRIPT_EOF
    
    chmod +x /usr/local/bin/nextcloud-add-ip
    
    # Create IP removal script
    cat > /usr/local/bin/nextcloud-remove-ip <<'SCRIPT_EOF'
#!/bin/bash

NC_PATH="/var/www/nextcloud"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <INDEX>"
    echo "To see current trusted domains with indices, run: nextcloud-list-ips"
    exit 1
fi

INDEX=$1

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Remove trusted domain
sudo -u www-data php "$NC_PATH/occ" config:system:delete trusted_domains $INDEX

echo "Removed trusted domain at index $INDEX"
echo ""
echo "Current trusted domains:"
sudo -u www-data php "$NC_PATH/occ" config:system:get trusted_domains

SCRIPT_EOF
    
    chmod +x /usr/local/bin/nextcloud-remove-ip
    
    # Create IP listing script
    cat > /usr/local/bin/nextcloud-list-ips <<'SCRIPT_EOF'
#!/bin/bash

NC_PATH="/var/www/nextcloud"

echo "Current Nextcloud trusted domains:"
echo "=================================="
sudo -u www-data php "$NC_PATH/occ" config:system:get trusted_domains

SCRIPT_EOF
    
    chmod +x /usr/local/bin/nextcloud-list-ips
    
    # Create backup script
    cat > /usr/local/bin/nextcloud-backup <<'SCRIPT_EOF'
#!/bin/bash

NC_PATH="/var/www/nextcloud"
NC_DATA_DIR="$(grep datadirectory $NC_PATH/config/config.php | cut -d "'" -f 4)"
BACKUP_DIR="/var/backups/nextcloud"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/backup_$DATE"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

echo "Starting Nextcloud backup..."

# Create backup directory
mkdir -p "$BACKUP_PATH"

# Enable maintenance mode
sudo -u www-data php "$NC_PATH/occ" maintenance:mode --on

# Backup database
DB_NAME=$(grep dbname "$NC_PATH/config/config.php" | cut -d "'" -f 4)
DB_USER=$(grep dbuser "$NC_PATH/config/config.php" | cut -d "'" -f 4)
DB_PASS=$(grep dbpassword "$NC_PATH/config/config.php" | cut -d "'" -f 4)

mysqldump --single-transaction -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_PATH/database.sql"

# Backup Nextcloud directory
tar -czf "$BACKUP_PATH/nextcloud.tar.gz" -C /var/www nextcloud

# Backup data directory (optional, can be large)
read -p "Backup data directory? This can be very large (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    tar -czf "$BACKUP_PATH/data.tar.gz" "$NC_DATA_DIR"
fi

# Disable maintenance mode
sudo -u www-data php "$NC_PATH/occ" maintenance:mode --off

echo "Backup completed: $BACKUP_PATH"
echo "Database: $BACKUP_PATH/database.sql"
echo "Nextcloud: $BACKUP_PATH/nextcloud.tar.gz"
[[ -f "$BACKUP_PATH/data.tar.gz" ]] && echo "Data: $BACKUP_PATH/data.tar.gz"

SCRIPT_EOF
    
    chmod +x /usr/local/bin/nextcloud-backup
    
    # Create system info script
    cat > /usr/local/bin/nextcloud-info <<'SCRIPT_EOF'
#!/bin/bash

NC_PATH="/var/www/nextcloud"

echo "Nextcloud Installation Information"
echo "=================================="
echo ""
echo "Installation Path: $NC_PATH"
echo "Data Directory: $(grep datadirectory $NC_PATH/config/config.php | cut -d "'" -f 4)"
echo "Database Name: $(grep dbname $NC_PATH/config/config.php | cut -d "'" -f 4)"
echo "Database User: $(grep dbuser $NC_PATH/config/config.php | cut -d "'" -f 4)"
echo ""
echo "Nextcloud Version:"
sudo -u www-data php "$NC_PATH/occ" status | grep version
echo ""
echo "PHP Version: $(php -v | head -1)"
echo ""
echo "Web Server:"
if systemctl is-active --quiet apache2; then
    echo "Apache (active)"
    apache2 -v | head -1
elif systemctl is-active --quiet nginx; then
    echo "Nginx (active)"
    nginx -v 2>&1
fi
echo ""
echo "Database Server:"
if systemctl is-active --quiet mariadb; then
    echo "MariaDB (active)"
    mysql --version
elif systemctl is-active --quiet mysql; then
    echo "MySQL (active)"
    mysql --version
fi
echo ""
echo "Trusted Domains:"
sudo -u www-data php "$NC_PATH/occ" config:system:get trusted_domains
echo ""
echo "Helper Commands Available:"
echo "  nextcloud-add-ip <IP/DOMAIN>  - Add trusted domain"
echo "  nextcloud-remove-ip <INDEX>   - Remove trusted domain"
echo "  nextcloud-list-ips            - List trusted domains"
echo "  nextcloud-backup              - Create backup"
echo "  nextcloud-info                - Show this info"

SCRIPT_EOF
    
    chmod +x /usr/local/bin/nextcloud-info
    
    print_message "success" "Helper scripts created"
}

final_setup() {
    print_message "info" "Performing final setup..."
    
    # Run Nextcloud maintenance commands
    cd "$NC_PATH"
    sudo -u www-data php occ db:add-missing-indices
    sudo -u www-data php occ db:convert-filecache-bigint --no-interaction
    
    # Set up log rotation
    cat > /etc/logrotate.d/nextcloud <<EOF
$NC_DATA_DIR/nextcloud.log {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    create 640 www-data www-data
}
EOF
    
    print_message "success" "Final setup completed"
}

display_summary() {
    local ip_address=$(hostname -I | awk '{print $1}')
    
    clear
    echo ""
    echo "=============================================="
    echo "     Nextcloud Installation Complete!"
    echo "=============================================="
    echo ""
    echo "Access Information:"
    echo "-------------------"
    echo "URL:           http://$NC_DOMAIN"
    [[ "$USE_SSL" == "yes" ]] && echo "Secure URL:    https://$NC_DOMAIN"
    echo "Local IP:      http://$ip_address"
    echo "Admin User:    $NC_ADMIN_USER"
    echo ""
    echo "File Storage:"
    echo "-------------"
    echo "Data Directory: $NC_DATA_DIR"
    echo "This directory contains all user files and can be accessed"
    echo "directly even if Nextcloud is down."
    echo ""
    echo "IP Management Commands:"
    echo "-----------------------"
    echo "Add IP/Domain:    nextcloud-add-ip <IP/DOMAIN>"
    echo "Remove IP:        nextcloud-remove-ip <INDEX>"
    echo "List IPs:         nextcloud-list-ips"
    echo ""
    echo "Other Commands:"
    echo "---------------"
    echo "System Info:      nextcloud-info"
    echo "Create Backup:    nextcloud-backup"
    echo ""
    echo "Important Notes:"
    echo "----------------"
    echo "1. If you change your IP address, use 'nextcloud-add-ip' to add it"
    echo "2. Your files are stored in: $NC_DATA_DIR"
    echo "3. Regular backups are recommended using 'nextcloud-backup'"
    echo "4. Installation log: $LOG_FILE"
    echo ""
    echo "Security Recommendations:"
    echo "-------------------------"
    echo "1. Enable firewall (ufw or iptables)"
    echo "2. Regular system updates: apt update && apt upgrade"
    echo "3. Monitor logs: $NC_DATA_DIR/nextcloud.log"
    [[ "$USE_SSL" != "yes" ]] && echo "4. Consider enabling SSL: Run 'certbot' for free SSL certificate"
    echo ""
    echo "=============================================="
}

#############################################################################
# Main Installation Flow
#############################################################################

main() {
    print_message "info" "Starting Nextcloud Installation Script v$SCRIPT_VERSION"
    print_message "info" "Installation log: $LOG_FILE"
    
    # Pre-installation checks
    check_root
    check_os
    check_internet
    detect_php_version
    check_existing_installation
    
    # Collect configuration
    collect_configuration
    
    # Installation
    install_dependencies
    configure_database
    download_nextcloud
    
    # Configure web server
    if [[ "$WEB_SERVER" == "apache" ]]; then
        configure_apache
    else
        configure_nginx
    fi
    
    # Continue installation
    configure_redis
    set_permissions
    install_nextcloud
    configure_cron
    configure_ssl
    create_helper_scripts
    final_setup
    
    # Display summary
    display_summary
    
    print_message "success" "Installation completed successfully!"
}

# Run main function
main "$@"
