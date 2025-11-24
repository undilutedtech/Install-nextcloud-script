#!/bin/bash

# Quick Nextcloud Error Checker
echo "==================================="
echo "Nextcloud Quick Error Check"
echo "==================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Please run as root: sudo $0"
   exit 1
fi

NC_PATH="/var/www/nextcloud"

# 1. Check most recent error in logs
echo "📋 MOST RECENT ERRORS:"
echo "----------------------"

# Apache error
if [[ -f /var/log/apache2/error.log ]]; then
    echo "Apache Error:"
    tail -3 /var/log/apache2/error.log | grep -E "(error|fatal|critical)" || echo "  No recent errors"
    echo ""
fi

# Nginx error
if [[ -f /var/log/nginx/error.log ]]; then
    echo "Nginx Error:"
    tail -3 /var/log/nginx/error.log | grep -E "(error|fatal|critical)" || echo "  No recent errors"
    echo ""
fi

# PHP error
php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
if [[ -f /var/log/php${php_version}-fpm.log ]]; then
    echo "PHP-FPM Error:"
    tail -3 /var/log/php${php_version}-fpm.log | grep -E "(error|fatal|critical)" || echo "  No recent errors"
    echo ""
fi

# 2. Check Nextcloud status
echo "🔍 NEXTCLOUD STATUS:"
echo "--------------------"
if [[ -f "$NC_PATH/occ" ]]; then
    sudo -u www-data php "$NC_PATH/occ" status 2>&1 | head -10
else
    echo "OCC command not found!"
fi
echo ""

# 3. Check critical issues
echo "⚠️  QUICK CHECKS:"
echo "-----------------"

# Check ownership
owner=$(stat -c %U "$NC_PATH" 2>/dev/null)
if [[ "$owner" == "www-data" ]]; then
    echo "✓ File ownership: OK"
else
    echo "✗ File ownership: WRONG (is $owner, should be www-data)"
    echo "  FIX: sudo chown -R www-data:www-data $NC_PATH"
fi

# Check config exists
if [[ -f "$NC_PATH/config/config.php" ]]; then
    echo "✓ Config file: EXISTS"
    
    # Check database connection
    db_name=$(grep "'dbname'" "$NC_PATH/config/config.php" | cut -d "'" -f 4)
    db_user=$(grep "'dbuser'" "$NC_PATH/config/config.php" | cut -d "'" -f 4)
    db_pass=$(grep "'dbpassword'" "$NC_PATH/config/config.php" | cut -d "'" -f 4)
    
    if mysql -u "$db_user" -p"$db_pass" -e "USE $db_name;" &>/dev/null; then
        echo "✓ Database connection: OK"
    else
        echo "✗ Database connection: FAILED"
        echo "  Check if MySQL/MariaDB is running: systemctl status mysql"
    fi
else
    echo "✗ Config file: MISSING"
fi

# Check PHP modules
missing_modules=()
for module in curl dom gd mbstring openssl pdo_mysql xml zip; do
    if ! php -m 2>/dev/null | grep -qi "^$module$"; then
        missing_modules+=("$module")
    fi
done

if [[ ${#missing_modules[@]} -eq 0 ]]; then
    echo "✓ PHP modules: ALL INSTALLED"
else
    echo "✗ PHP modules missing: ${missing_modules[*]}"
    echo "  FIX: sudo apt-get install php${php_version}-{${missing_modules[*]}}"
fi

# Check .htaccess
if [[ -f "$NC_PATH/.htaccess" ]]; then
    echo "✓ .htaccess: EXISTS"
else
    echo "✗ .htaccess: MISSING"
    echo "  FIX: sudo -u www-data php $NC_PATH/occ maintenance:update:htaccess"
fi

echo ""
echo "==================================="
echo "📌 QUICK FIXES TO TRY:"
echo "==================================="
echo ""
echo "1. Fix permissions:"
echo "   sudo chown -R www-data:www-data $NC_PATH"
echo "   sudo chown -R www-data:www-data /mnt/nextcloud-data  # or your data dir"
echo ""
echo "2. Restart services:"
echo "   sudo systemctl restart apache2  # or nginx"
echo "   sudo systemctl restart mysql    # or mariadb"
echo "   sudo systemctl restart redis-server"
echo "   sudo systemctl restart php${php_version}-fpm  # if using nginx"
echo ""
echo "3. Run repair:"
echo "   sudo -u www-data php $NC_PATH/occ maintenance:repair"
echo ""
echo "4. For detailed fix, run:"
echo "   sudo ./fix_internal_error.sh"
echo ""
echo "5. Check detailed logs:"
echo "   sudo tail -f /var/log/apache2/error.log  # or nginx/error.log"
