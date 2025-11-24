#!/bin/bash

#############################################################################
# Quick Fix for Nginx Duplicate Directive Error
# Fixes: "root" directive is duplicate error
#############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "Nginx Duplicate Directive Fix"
echo "=================================="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root:${NC} sudo $0"
    exit 1
fi

NGINX_CONF="/etc/nginx/sites-available/nextcloud"

if [[ ! -f "$NGINX_CONF" ]]; then
    echo -e "${RED}Error:${NC} Nginx configuration not found at $NGINX_CONF"
    echo "Run the fix_nginx_config.sh script instead"
    exit 1
fi

# Backup the configuration
echo "Creating backup..."
cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${GREEN}✓${NC} Backup created"

echo "Fixing duplicate directives..."

# Create a temporary file
TEMP_FILE=$(mktemp)

# Process the file to remove duplicates
awk '
    /^[[:space:]]*root[[:space:]]/ { 
        if (!root_seen) {
            root_seen = 1
            print
        } else {
            next
        }
    }
    /^[[:space:]]*client_max_body_size[[:space:]]/ { 
        if (!client_seen) {
            client_seen = 1
            print
        } else {
            next
        }
    }
    /^[[:space:]]*fastcgi_buffers[[:space:]]/ { 
        if (!buffer_seen) {
            buffer_seen = 1
            print
        } else {
            next
        }
    }
    /^[[:space:]]*gzip[[:space:]](on|off)/ { 
        if (!gzip_seen) {
            gzip_seen = 1
            print
        } else {
            next
        }
    }
    /^[[:space:]]*gzip_vary/ { 
        if (!gzip_vary_seen) {
            gzip_vary_seen = 1
            print
        } else {
            next
        }
    }
    /^[[:space:]]*gzip_comp_level/ { 
        if (!gzip_comp_seen) {
            gzip_comp_seen = 1
            print
        } else {
            next
        }
    }
    /^[[:space:]]*gzip_min_length/ { 
        if (!gzip_min_seen) {
            gzip_min_seen = 1
            print
        } else {
            next
        }
    }
    /^[[:space:]]*gzip_types/ { 
        if (!gzip_types_seen) {
            gzip_types_seen = 1
            print
        } else {
            next
        }
    }
    !/^[[:space:]]*(root|client_max_body_size|fastcgi_buffers|gzip)/ { print }
' "$NGINX_CONF" > "$TEMP_FILE"

# Replace the original file
mv "$TEMP_FILE" "$NGINX_CONF"
echo -e "${GREEN}✓${NC} Duplicate directives removed"

# Test the configuration
echo -n "Testing Nginx configuration... "
if nginx -t &>/dev/null; then
    echo -e "${GREEN}✓ Valid${NC}"
    
    # Reload Nginx
    echo -n "Reloading Nginx... "
    systemctl reload nginx
    echo -e "${GREEN}✓${NC}"
    
    echo ""
    echo -e "${GREEN}=================================="
    echo "Configuration Fixed!"
    echo "=================================="
    echo ""
    echo "Nextcloud should now be accessible."
    
else
    echo -e "${RED}✗ Failed${NC}"
    echo ""
    echo "Configuration test failed. Error output:"
    nginx -t
    echo ""
    echo "Restoring backup..."
    cp "${NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)" "$NGINX_CONF"
    echo ""
    echo "Please run the comprehensive fix instead:"
    echo "  sudo ./fix_nginx_config.sh"
    exit 1
fi
