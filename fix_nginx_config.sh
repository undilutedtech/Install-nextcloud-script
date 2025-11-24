#!/bin/bash

#############################################################################
# Nginx Configuration Fix for Nextcloud
# Fixes configuration issues from sed delimiter problems
#############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=================================="
echo "Nginx Configuration Fix"
echo "=================================="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root:${NC} sudo $0"
    exit 1
fi

# Get configuration values
NC_PATH="/var/www/nextcloud"
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)

echo "Enter your domain/IP address for Nextcloud:"
read -p "Domain/IP: " NC_DOMAIN

if [[ -z "$NC_DOMAIN" ]]; then
    # Try to get from existing config
    if [[ -f "$NC_PATH/config/config.php" ]]; then
        NC_DOMAIN=$(grep "'trusted_domains'" -A 5 "$NC_PATH/config/config.php" | grep -oP "^\s+1\s+=>\s+'\K[^']+")
        echo "Using domain from config: $NC_DOMAIN"
    else
        echo -e "${RED}Domain cannot be empty${NC}"
        exit 1
    fi
fi

echo ""
echo "Configuration:"
echo "• PHP Version: $PHP_VERSION"
echo "• Domain: $NC_DOMAIN"
echo "• Nextcloud Path: $NC_PATH"
echo ""

# Backup existing configuration
if [[ -f /etc/nginx/sites-available/nextcloud ]]; then
    echo "Backing up existing configuration..."
    cp /etc/nginx/sites-available/nextcloud /etc/nginx/sites-available/nextcloud.backup.$(date +%Y%m%d_%H%M%S)
fi

echo "Creating corrected Nginx configuration..."

# Create proper Nginx configuration
cat > /etc/nginx/sites-available/nextcloud <<EOF
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
        return 301 \$scheme://\$host:\$server_port/remote.php/dav;
    }
    
    location = /.well-known/caldav {
        return 301 \$scheme://\$host:\$server_port/remote.php/dav;
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
    
    location ~ ^\/(?:index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+)\.php(?:\$|\/) {
        fastcgi_split_path_info ^(.+?\.php)(\/.*|\$);
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS off;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }
    
    location ~ ^\/(?:updater|oc[ms]-provider)(?:\$|\/) {
        try_files \$uri/ =404;
        index index.php;
    }
    
    location ~ \.(?:css|js|woff2?|svg|gif|map)\$ {
        try_files \$uri /index.php\$request_uri;
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
    
    location ~ \.(?:png|html|ttf|ico|jpg|jpeg|bcmap)\$ {
        try_files \$uri /index.php\$request_uri;
        access_log off;
    }
}
EOF

echo -e "${GREEN}✓${NC} Configuration created"

# Test configuration
echo -n "Testing Nginx configuration... "
if nginx -t &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "Configuration test failed. Output:"
    nginx -t
    exit 1
fi

# Enable site if not already enabled
if [[ ! -L /etc/nginx/sites-enabled/nextcloud ]]; then
    echo -n "Enabling Nextcloud site... "
    ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
    echo -e "${GREEN}✓${NC}"
fi

# Remove default site if exists
if [[ -L /etc/nginx/sites-enabled/default ]]; then
    echo -n "Removing default site... "
    rm -f /etc/nginx/sites-enabled/default
    echo -e "${GREEN}✓${NC}"
fi

# Restart services
echo "Restarting services..."
systemctl restart nginx
echo -e "${GREEN}✓${NC} Nginx restarted"

systemctl restart php${PHP_VERSION}-fpm
echo -e "${GREEN}✓${NC} PHP-FPM restarted"

echo ""
echo -e "${GREEN}=================================="
echo "Configuration Fixed!"
echo "=================================="
echo ""
echo "You should now be able to access Nextcloud at:"
echo "  http://$NC_DOMAIN"
echo ""
echo "If you still have issues, run:"
echo "  sudo ./fix_internal_error.sh"
