#!/bin/bash

# Nextcloud Quick Permissions Fix
# This fixes the most common cause of Internal Server Error

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "================================"
echo "Nextcloud Permissions Quick Fix"
echo "================================"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root:${NC} sudo $0"
   exit 1
fi

NC_PATH="/var/www/nextcloud"

# Get data directory from config
if [[ -f "$NC_PATH/config/config.php" ]]; then
    DATA_DIR=$(grep datadirectory "$NC_PATH/config/config.php" | cut -d "'" -f 4)
else
    DATA_DIR="/mnt/nextcloud-data"  # Default
    echo "Warning: Using default data directory path: $DATA_DIR"
fi

echo "Fixing permissions..."
echo "• Nextcloud path: $NC_PATH"
echo "• Data directory: $DATA_DIR"
echo ""

# Fix Nextcloud directory
echo -n "Setting ownership for Nextcloud files... "
chown -R www-data:www-data "$NC_PATH"
echo -e "${GREEN}✓${NC}"

# Fix data directory
if [[ -d "$DATA_DIR" ]]; then
    echo -n "Setting ownership for data directory... "
    chown -R www-data:www-data "$DATA_DIR"
    echo -e "${GREEN}✓${NC}"
fi

# Fix specific permissions
echo -n "Setting directory permissions... "
find "$NC_PATH" -type d -exec chmod 755 {} \; 2>/dev/null
echo -e "${GREEN}✓${NC}"

echo -n "Setting file permissions... "
find "$NC_PATH" -type f -exec chmod 644 {} \; 2>/dev/null
echo -e "${GREEN}✓${NC}"

# Fix config if it exists
if [[ -f "$NC_PATH/config/config.php" ]]; then
    echo -n "Setting config permissions... "
    chmod 640 "$NC_PATH/config/config.php"
    chown www-data:www-data "$NC_PATH/config/config.php"
    echo -e "${GREEN}✓${NC}"
fi

# Fix .htaccess
if [[ ! -f "$NC_PATH/.htaccess" ]] && [[ -f "$NC_PATH/occ" ]]; then
    echo -n "Regenerating .htaccess... "
    sudo -u www-data php "$NC_PATH/occ" maintenance:update:htaccess 2>/dev/null
    echo -e "${GREEN}✓${NC}"
fi

# Restart services
echo ""
echo "Restarting services..."

# Web server
if systemctl is-active --quiet apache2; then
    echo -n "Restarting Apache... "
    systemctl restart apache2
    echo -e "${GREEN}✓${NC}"
elif systemctl is-active --quiet nginx; then
    echo -n "Restarting Nginx... "
    systemctl restart nginx
    echo -e "${GREEN}✓${NC}"
    
    # PHP-FPM
    php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    echo -n "Restarting PHP-FPM... "
    systemctl restart php${php_version}-fpm 2>/dev/null
    echo -e "${GREEN}✓${NC}"
fi

# Redis
if systemctl is-active --quiet redis-server; then
    echo -n "Restarting Redis... "
    systemctl restart redis-server
    echo -e "${GREEN}✓${NC}"
fi

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Permissions fixed!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Try accessing Nextcloud again."
echo ""
echo "If error persists, run:"
echo "  sudo ./quick_error_check.sh   # to see specific errors"
echo "  sudo ./fix_internal_error.sh  # for comprehensive fix"
