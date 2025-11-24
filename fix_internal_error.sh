#!/bin/bash

#############################################################################
# Nextcloud Internal Server Error Fix Script
# Description: Diagnoses and fixes common causes of Internal Server Error
# Version: 1.0
#############################################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NC_PATH="/var/www/nextcloud"
LOG_FILE="/tmp/nextcloud_fix_$(date +%Y%m%d_%H%M%S).log"

#############################################################################
# Helper Functions
#############################################################################

print_header() {
    echo -e "\n${BLUE}==== $1 ====${NC}" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOG_FILE"
}

print_fix() {
    echo -e "${GREEN}➤${NC} $1" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

#############################################################################
# Diagnostic Functions
#############################################################################

check_error_logs() {
    print_header "Checking Error Logs"
    
    # Check Apache error log
    if [[ -f /var/log/apache2/error.log ]]; then
        print_info "Recent Apache errors:"
        tail -10 /var/log/apache2/error.log | grep -E "(error|fatal|critical)" | tail -5 | while IFS= read -r line; do
            echo "  $line" | tee -a "$LOG_FILE"
        done
    fi
    
    # Check Nginx error log
    if [[ -f /var/log/nginx/error.log ]]; then
        print_info "Recent Nginx errors:"
        tail -10 /var/log/nginx/error.log | grep -E "(error|fatal|critical)" | tail -5 | while IFS= read -r line; do
            echo "  $line" | tee -a "$LOG_FILE"
        done
    fi
    
    # Check PHP error log
    local php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    if [[ -f /var/log/php${php_version}-fpm.log ]]; then
        print_info "Recent PHP-FPM errors:"
        tail -10 /var/log/php${php_version}-fpm.log | grep -E "(error|fatal|critical)" | tail -5 | while IFS= read -r line; do
            echo "  $line" | tee -a "$LOG_FILE"
        done
    fi
    
    # Check Nextcloud log
    if [[ -f "$NC_PATH/config/config.php" ]]; then
        local data_dir=$(grep datadirectory "$NC_PATH/config/config.php" | cut -d "'" -f 4)
        if [[ -f "$data_dir/nextcloud.log" ]]; then
            print_info "Recent Nextcloud errors:"
            tail -5 "$data_dir/nextcloud.log" | while IFS= read -r line; do
                echo "  ${line:0:200}..." | tee -a "$LOG_FILE"
            done
        fi
    fi
}

check_php_configuration() {
    print_header "Checking PHP Configuration"
    
    local php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    print_info "PHP Version: $php_version"
    
    # Check memory limit
    local memory_limit=$(php -r "echo ini_get('memory_limit');" 2>/dev/null)
    if [[ "${memory_limit%M}" -lt 512 ]]; then
        print_error "PHP memory_limit is too low: $memory_limit (should be at least 512M)"
        print_fix "Fixing PHP memory limit..."
        
        # Fix for Apache
        if [[ -f /etc/php/$php_version/apache2/php.ini ]]; then
            sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/$php_version/apache2/php.ini
        fi
        
        # Fix for FPM
        if [[ -f /etc/php/$php_version/fpm/php.ini ]]; then
            sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/$php_version/fpm/php.ini
        fi
        
        # Fix for CLI
        if [[ -f /etc/php/$php_version/cli/php.ini ]]; then
            sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/$php_version/cli/php.ini
        fi
        
        print_success "PHP memory limit updated to 512M"
    else
        print_success "PHP memory_limit is OK: $memory_limit"
    fi
    
    # Check upload sizes
    local upload_max=$(php -r "echo ini_get('upload_max_filesize');" 2>/dev/null)
    local post_max=$(php -r "echo ini_get('post_max_size');" 2>/dev/null)
    
    print_info "upload_max_filesize: $upload_max"
    print_info "post_max_size: $post_max"
}

check_required_php_modules() {
    print_header "Checking Required PHP Modules"
    
    local missing_modules=()
    local required_modules=(
        "curl" "dom" "gd" "mbstring" "openssl"
        "pdo_mysql" "session" "xml" "zip" "json"
        "libxml" "SimpleXML" "XMLWriter" "XMLReader" "ctype"
    )
    
    for module in "${required_modules[@]}"; do
        if ! php -m 2>/dev/null | grep -qi "^$module$"; then
            print_error "Missing required PHP module: $module"
            missing_modules+=("$module")
        else
            print_success "PHP module $module is installed"
        fi
    done
    
    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        print_fix "Installing missing PHP modules..."
        local php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
        
        # Map module names to package names
        for module in "${missing_modules[@]}"; do
            case $module in
                "pdo_mysql") pkg="php${php_version}-mysql" ;;
                "dom"|"xml"|"SimpleXML"|"XMLWriter"|"XMLReader") pkg="php${php_version}-xml" ;;
                *) pkg="php${php_version}-${module}" ;;
            esac
            
            apt-get install -y "$pkg" 2>/dev/null || print_warning "Could not install $pkg"
        done
        
        print_info "Restarting web server..."
        systemctl restart apache2 2>/dev/null || systemctl restart nginx 2>/dev/null
        systemctl restart php${php_version}-fpm 2>/dev/null
    fi
}

check_file_permissions() {
    print_header "Checking File Permissions"
    
    local issues_found=false
    
    # Check Nextcloud directory ownership
    if [[ -d "$NC_PATH" ]]; then
        local owner=$(stat -c %U "$NC_PATH")
        if [[ "$owner" != "www-data" ]]; then
            print_error "Incorrect owner for $NC_PATH: $owner (should be www-data)"
            print_fix "Fixing ownership..."
            chown -R www-data:www-data "$NC_PATH"
            print_success "Ownership fixed"
            issues_found=true
        else
            print_success "Nextcloud directory ownership is correct"
        fi
    fi
    
    # Check data directory
    if [[ -f "$NC_PATH/config/config.php" ]]; then
        local data_dir=$(grep datadirectory "$NC_PATH/config/config.php" | cut -d "'" -f 4)
        if [[ -d "$data_dir" ]]; then
            local data_owner=$(stat -c %U "$data_dir")
            if [[ "$data_owner" != "www-data" ]]; then
                print_error "Incorrect owner for data directory: $data_owner"
                print_fix "Fixing data directory ownership..."
                chown -R www-data:www-data "$data_dir"
                print_success "Data directory ownership fixed"
                issues_found=true
            else
                print_success "Data directory ownership is correct"
            fi
        fi
    fi
    
    # Check config file permissions
    if [[ -f "$NC_PATH/config/config.php" ]]; then
        local config_perms=$(stat -c %a "$NC_PATH/config/config.php")
        local config_owner=$(stat -c %U "$NC_PATH/config/config.php")
        
        if [[ "$config_owner" != "www-data" ]]; then
            print_error "Incorrect config.php owner: $config_owner"
            print_fix "Fixing config.php ownership..."
            chown www-data:www-data "$NC_PATH/config/config.php"
            print_success "Config ownership fixed"
        fi
        
        if [[ "$config_perms" != "640" ]] && [[ "$config_perms" != "644" ]]; then
            print_warning "Config permissions: $config_perms (fixing to 640)"
            chmod 640 "$NC_PATH/config/config.php"
            print_success "Config permissions fixed"
        fi
    fi
    
    # Fix .htaccess if missing
    if [[ ! -f "$NC_PATH/.htaccess" ]]; then
        print_error ".htaccess file is missing"
        print_fix "Regenerating .htaccess..."
        sudo -u www-data php "$NC_PATH/occ" maintenance:update:htaccess 2>/dev/null
        print_success ".htaccess regenerated"
    fi
}

check_database_connection() {
    print_header "Checking Database Connection"
    
    if [[ ! -f "$NC_PATH/config/config.php" ]]; then
        print_error "config.php not found - Nextcloud may not be installed"
        return 1
    fi
    
    # Extract database credentials
    local db_type=$(grep "'dbtype'" "$NC_PATH/config/config.php" | cut -d "'" -f 4)
    local db_name=$(grep "'dbname'" "$NC_PATH/config/config.php" | cut -d "'" -f 4)
    local db_user=$(grep "'dbuser'" "$NC_PATH/config/config.php" | cut -d "'" -f 4)
    local db_pass=$(grep "'dbpassword'" "$NC_PATH/config/config.php" | cut -d "'" -f 4)
    local db_host=$(grep "'dbhost'" "$NC_PATH/config/config.php" | cut -d "'" -f 4)
    
    db_host=${db_host:-localhost}
    
    print_info "Database type: $db_type"
    print_info "Database name: $db_name"
    print_info "Database host: $db_host"
    
    # Test connection
    if mysql -h "$db_host" -u "$db_user" -p"$db_pass" -e "USE $db_name; SELECT COUNT(*) FROM oc_users;" &>/dev/null; then
        print_success "Database connection successful"
    else
        print_error "Cannot connect to database"
        
        # Check if database service is running
        if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
            print_fix "Starting database service..."
            systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null
            print_success "Database service started"
        fi
        
        # Verify database exists
        if ! mysql -e "SHOW DATABASES;" 2>/dev/null | grep -q "$db_name"; then
            print_error "Database '$db_name' does not exist"
            print_info "You may need to recreate the database and user"
        fi
    fi
}

check_redis_cache() {
    print_header "Checking Redis Cache"
    
    # Check if Redis is configured in Nextcloud
    if grep -q "memcache.locking.*Redis" "$NC_PATH/config/config.php" 2>/dev/null; then
        print_info "Redis is configured in Nextcloud"
        
        # Check if Redis service is running
        if ! systemctl is-active --quiet redis-server; then
            print_error "Redis service is not running"
            print_fix "Starting Redis..."
            systemctl start redis-server
            systemctl enable redis-server
            print_success "Redis started"
        else
            print_success "Redis service is running"
        fi
        
        # Check Redis socket permissions
        if [[ -S /var/run/redis/redis-server.sock ]]; then
            local redis_perms=$(stat -c %a /var/run/redis/redis-server.sock)
            if [[ "$redis_perms" != "770" ]] && [[ "$redis_perms" != "777" ]]; then
                print_warning "Redis socket permissions may be incorrect: $redis_perms"
                print_fix "Fixing Redis socket permissions..."
                chmod 770 /var/run/redis/redis-server.sock
                usermod -a -G redis www-data
                print_success "Redis permissions fixed"
            fi
        fi
    else
        print_info "Redis is not configured (optional)"
    fi
}

check_apache_configuration() {
    print_header "Checking Apache Configuration"
    
    if ! systemctl is-active --quiet apache2; then
        print_info "Apache is not running (might be using Nginx)"
        return
    fi
    
    # Check required modules
    local required_modules=("rewrite" "headers" "env" "dir" "mime")
    for module in "${required_modules[@]}"; do
        if ! apache2ctl -M 2>/dev/null | grep -q "${module}_module"; then
            print_error "Apache module $module is not enabled"
            print_fix "Enabling $module..."
            a2enmod "$module" &>/dev/null
            print_success "Module $module enabled"
        else
            print_success "Apache module $module is enabled"
        fi
    done
    
    # Check if Nextcloud site is enabled
    if [[ ! -f /etc/apache2/sites-enabled/nextcloud.conf ]] && [[ ! -f /etc/apache2/sites-enabled/000-default.conf ]]; then
        print_error "No Apache site configuration found for Nextcloud"
        if [[ -f /etc/apache2/sites-available/nextcloud.conf ]]; then
            print_fix "Enabling Nextcloud site..."
            a2ensite nextcloud.conf
            print_success "Nextcloud site enabled"
        fi
    fi
    
    # Test Apache configuration
    if ! apache2ctl -t &>/dev/null; then
        print_error "Apache configuration has syntax errors"
        apache2ctl -t 2>&1 | tee -a "$LOG_FILE"
    else
        print_success "Apache configuration is valid"
    fi
}

check_nginx_configuration() {
    print_header "Checking Nginx Configuration"
    
    if ! systemctl is-active --quiet nginx; then
        print_info "Nginx is not running (might be using Apache)"
        return
    fi
    
    # Check if Nextcloud site is enabled
    if [[ ! -f /etc/nginx/sites-enabled/nextcloud ]] && [[ ! -f /etc/nginx/sites-enabled/default ]]; then
        print_error "No Nginx site configuration found for Nextcloud"
        if [[ -f /etc/nginx/sites-available/nextcloud ]]; then
            print_fix "Enabling Nextcloud site..."
            ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
            print_success "Nextcloud site enabled"
        fi
    fi
    
    # Test Nginx configuration
    if ! nginx -t &>/dev/null; then
        print_error "Nginx configuration has syntax errors"
        nginx -t 2>&1 | tee -a "$LOG_FILE"
    else
        print_success "Nginx configuration is valid"
    fi
    
    # Check PHP-FPM
    local php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    if ! systemctl is-active --quiet "php${php_version}-fpm"; then
        print_error "PHP-FPM is not running"
        print_fix "Starting PHP-FPM..."
        systemctl start "php${php_version}-fpm"
        systemctl enable "php${php_version}-fpm"
        print_success "PHP-FPM started"
    else
        print_success "PHP-FPM is running"
    fi
}

run_nextcloud_repair() {
    print_header "Running Nextcloud Repair Commands"
    
    if [[ ! -f "$NC_PATH/occ" ]]; then
        print_error "OCC command not found"
        return
    fi
    
    # Disable maintenance mode first
    print_info "Ensuring maintenance mode is off..."
    sudo -u www-data php "$NC_PATH/occ" maintenance:mode --off &>/dev/null
    
    # Run repair
    print_info "Running Nextcloud repair..."
    sudo -u www-data php "$NC_PATH/occ" maintenance:repair 2>&1 | tee -a "$LOG_FILE"
    
    # Update .htaccess
    print_info "Updating .htaccess..."
    sudo -u www-data php "$NC_PATH/occ" maintenance:update:htaccess 2>&1 | tee -a "$LOG_FILE"
    
    # Add missing indices
    print_info "Adding missing database indices..."
    sudo -u www-data php "$NC_PATH/occ" db:add-missing-indices 2>&1 | tee -a "$LOG_FILE"
    
    # Clear cache
    print_info "Clearing cache..."
    sudo -u www-data php "$NC_PATH/occ" cache:clear 2>&1 | tee -a "$LOG_FILE"
    
    print_success "Nextcloud repair completed"
}

restart_services() {
    print_header "Restarting Services"
    
    # Restart web server
    if systemctl is-active --quiet apache2; then
        print_info "Restarting Apache..."
        systemctl restart apache2
        print_success "Apache restarted"
    elif systemctl is-active --quiet nginx; then
        print_info "Restarting Nginx..."
        systemctl restart nginx
        print_success "Nginx restarted"
        
        # Also restart PHP-FPM for Nginx
        local php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
        systemctl restart "php${php_version}-fpm" 2>/dev/null
        print_success "PHP-FPM restarted"
    fi
    
    # Restart Redis if configured
    if systemctl is-active --quiet redis-server; then
        print_info "Restarting Redis..."
        systemctl restart redis-server
        print_success "Redis restarted"
    fi
}

display_summary() {
    print_header "Summary and Next Steps"
    
    echo ""
    print_info "Diagnostic complete. Log saved to: $LOG_FILE"
    echo ""
    
    # Count issues
    local errors=$(grep -c "✗" "$LOG_FILE" || echo 0)
    local fixed=$(grep -c "➤" "$LOG_FILE" || echo 0)
    
    if [[ $errors -eq 0 ]]; then
        print_success "No critical issues found!"
    else
        print_warning "Found and attempted to fix $fixed issue(s)"
        
        echo ""
        print_info "If the error persists, check:"
        echo "  1. Web server error log:"
        if [[ -f /var/log/apache2/error.log ]]; then
            echo "     sudo tail -f /var/log/apache2/error.log"
        elif [[ -f /var/log/nginx/error.log ]]; then
            echo "     sudo tail -f /var/log/nginx/error.log"
        fi
        
        echo "  2. Nextcloud log:"
        if [[ -f "$NC_PATH/config/config.php" ]]; then
            local data_dir=$(grep datadirectory "$NC_PATH/config/config.php" | cut -d "'" -f 4)
            echo "     sudo tail -f $data_dir/nextcloud.log"
        fi
        
        echo "  3. Enable debug mode (temporarily):"
        echo "     sudo -u www-data php $NC_PATH/occ config:system:set debug --value=true"
        echo "     (Remember to disable: --value=false)"
    fi
    
    echo ""
    print_info "Try accessing Nextcloud again. If issues persist, review the log file."
}

#############################################################################
# Main
#############################################################################

main() {
    clear
    echo "=========================================="
    echo "   Nextcloud Internal Error Fix Tool"
    echo "=========================================="
    echo ""
    
    check_root
    
    print_info "Starting diagnostic and repair process..."
    print_info "This will attempt to identify and fix common issues"
    echo ""
    
    # Run all checks and fixes
    check_error_logs
    check_php_configuration
    check_required_php_modules
    check_file_permissions
    check_database_connection
    check_redis_cache
    
    # Check web server specific configuration
    check_apache_configuration
    check_nginx_configuration
    
    # Run Nextcloud repair
    run_nextcloud_repair
    
    # Restart services
    restart_services
    
    # Display summary
    display_summary
}

# Run main function
main "$@"
