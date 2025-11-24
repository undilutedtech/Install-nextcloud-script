# Nextcloud Installation Script with Separated File Storage

## Overview

This comprehensive bash script automates the installation of the latest Nextcloud server with special features for separated file storage and IP address management. It's designed to provide a production-ready Nextcloud installation with enhanced flexibility and accessibility.

## Key Features

### 1. **Separated File Storage**
- Files are stored in a custom directory (e.g., `/mnt/nextcloud-data`) separate from the Nextcloud installation
- Direct file access remains possible even when Nextcloud services are down
- Easier backup and migration of user data
- Flexible storage location configuration

### 2. **IP Address Management**
- Dynamic trusted domains configuration
- Helper scripts to add/remove IP addresses without lockouts
- Automatic local IP detection and configuration
- Support for multiple access points (domain, IP, localhost)

### 3. **No Hardcoded Values**
- Interactive configuration prompts
- Secure password input with confirmation
- Customizable installation paths
- Database credentials configuration
- Domain/IP configuration

### 4. **Production-Ready Setup**
- Apache or Nginx web server support
- MariaDB/MySQL database with optimized settings
- Redis caching for performance
- PHP-FPM configuration for better resource management
- SSL/HTTPS support with Let's Encrypt
- Automated cron jobs for background tasks

## System Requirements

### Supported Operating Systems
- Ubuntu 20.04 LTS or later
- Debian 11 or later

### Hardware Requirements
- **Minimum:** 512MB RAM, 1 CPU core
- **Recommended:** 2GB+ RAM, 2+ CPU cores
- **Storage:** 10GB for system + space for user data

### Network Requirements
- Static IP address or domain name
- Internet connection for package downloads
- Ports 80/443 open for web access

## Installation

### 1. Download the Script
```bash
wget https://your-server/install_nextcloud.sh
# or
curl -O https://your-server/install_nextcloud.sh
```

### 2. Make it Executable
```bash
chmod +x install_nextcloud.sh
```

### 3. Run as Root
```bash
sudo ./install_nextcloud.sh
```

## Installation Process

The script will guide you through the following steps:

1. **System Checks**
   - OS compatibility verification
   - Root privileges check
   - Internet connectivity test
   - Existing installation detection

2. **Configuration Collection**
   - Web server selection (Apache/Nginx)
   - Database type (MariaDB/MySQL)
   - Database credentials
   - Data directory location
   - Admin credentials
   - Domain/IP configuration
   - SSL certificate option

3. **Automated Installation**
   - System dependencies installation
   - Database setup and optimization
   - Nextcloud download and extraction
   - Web server configuration
   - PHP optimization
   - Redis cache setup
   - File permissions configuration
   - Cron job setup

## Helper Commands

After installation, the following commands are available:

### IP/Domain Management
```bash
# Add a new trusted domain or IP
nextcloud-add-ip 192.168.1.100
nextcloud-add-ip cloud.example.com

# Remove a trusted domain by index
nextcloud-remove-ip 3

# List all trusted domains with indices
nextcloud-list-ips
```

### System Management
```bash
# Display system information
nextcloud-info

# Create a backup
nextcloud-backup
```

## File Storage Structure

```
/var/www/nextcloud/          # Nextcloud application files
├── apps/                    # Installed apps
├── config/                  # Configuration files
├── core/                    # Core files
└── ...

/mnt/nextcloud-data/         # User data (customizable)
├── admin/                   # Admin user files
├── files_external/          # External storage
├── appdata_*/              # App data
└── nextcloud.log           # Application log
```

## Configuration Files

### Main Configuration
- **Location:** `/var/www/nextcloud/config/config.php`
- Contains database settings, trusted domains, and system configuration

### Web Server Configuration
- **Apache:** `/etc/apache2/sites-available/nextcloud.conf`
- **Nginx:** `/etc/nginx/sites-available/nextcloud`

### Database Configuration
- **MariaDB/MySQL:** `/etc/mysql/conf.d/nextcloud.cnf`

### PHP Configuration
- **Apache:** `/etc/php/8.x/apache2/php.ini`
- **Nginx:** `/etc/php/8.x/fpm/php.ini`

## Security Features

1. **Password Security**
   - Minimum 8-character passwords
   - Secure password prompting with confirmation
   - No passwords stored in plain text

2. **File Permissions**
   - Proper ownership (www-data)
   - Restricted access to data directory
   - Configuration file protection

3. **Network Security**
   - SSL/TLS support with Let's Encrypt
   - Security headers configuration
   - Trusted domains validation

4. **Database Security**
   - Separate database user with limited privileges
   - Optimized transaction isolation
   - Binary logging configuration

## Troubleshooting

### Installation Issues

**Problem:** "root" directive is duplicate in /etc/nginx/sites-enabled/nextcloud
```bash
# This error occurs when Nginx configuration has duplicate directives
# Quick fix:
sudo ./quick_nginx_fix.sh

# Or complete reconfiguration:
sudo ./fix_nginx_config.sh
```

**Problem:** sed: unknown option to 's' error during Nginx configuration
```bash
# This has been fixed in the latest version of the script
# The issue was with sed delimiter conflicts with path slashes
# If you encounter this, download the updated script
```

### Database Issues

**Problem:** ERROR 1356 or password-related errors during installation
```bash
# This occurs with newer MySQL/MariaDB versions
# The script now handles this automatically, but if issues persist:

# For fresh installation, reset root password manually:
sudo mysql
ALTER USER 'root'@'localhost' IDENTIFIED BY 'YourNewPassword';
FLUSH PRIVILEGES;
exit
```

### Access Issues

**Problem:** Can't access Nextcloud after IP change
```bash
# Solution: Add new IP to trusted domains
sudo nextcloud-add-ip YOUR_NEW_IP
```

**Problem:** "Access through untrusted domain" error
```bash
# Solution: List current domains and add the missing one
sudo nextcloud-list-ips
sudo nextcloud-add-ip your-domain.com
```

### Performance Issues

**Problem:** Slow performance
```bash
# Check Redis status
sudo systemctl status redis-server

# Check PHP-FPM status (for Nginx)
sudo systemctl status php8.2-fpm

# Review Nextcloud status
sudo -u www-data php /var/www/nextcloud/occ status
```

### File Access

**Problem:** Need direct file access
```bash
# Files are stored in the configured data directory
cd /mnt/nextcloud-data  # or your configured location

# User files are in username/files/
ls -la username/files/
```

## Maintenance

### Regular Updates
```bash
# System updates
sudo apt update && sudo apt upgrade

# Nextcloud updates (via web interface or occ)
sudo -u www-data php /var/www/nextcloud/occ upgrade
```

### Backup Strategy
```bash
# Use the provided backup script
sudo nextcloud-backup

# Manual backup of critical components
# 1. Database
mysqldump nextcloud > backup.sql

# 2. Data directory
tar -czf data-backup.tar.gz /mnt/nextcloud-data

# 3. Configuration
tar -czf config-backup.tar.gz /var/www/nextcloud/config
```

### Log Monitoring
```bash
# Nextcloud log
tail -f /mnt/nextcloud-data/nextcloud.log

# Web server logs
# Apache
tail -f /var/log/apache2/nextcloud_error.log

# Nginx
tail -f /var/log/nginx/error.log
```

## Advanced Configuration

### Adding External Storage
```bash
sudo -u www-data php /var/www/nextcloud/occ app:enable files_external
```

### Enabling Additional Apps
```bash
# List available apps
sudo -u www-data php /var/www/nextcloud/occ app:list

# Enable an app
sudo -u www-data php /var/www/nextcloud/occ app:enable calendar
```

### Performance Tuning
```bash
# Increase PHP memory limit
sudo sed -i 's/memory_limit = .*/memory_limit = 1024M/' /etc/php/8.2/apache2/php.ini

# Restart web server
sudo systemctl restart apache2  # or nginx
```

## Recovery Procedures

### Database Recovery
```bash
# Restore from backup
mysql -u root -p nextcloud < backup.sql

# Repair tables
sudo -u www-data php /var/www/nextcloud/occ maintenance:repair
```

### File Recovery
```bash
# Restore data directory
tar -xzf data-backup.tar.gz -C /

# Fix permissions
sudo chown -R www-data:www-data /mnt/nextcloud-data

# Rescan files
sudo -u www-data php /var/www/nextcloud/occ files:scan --all
```

## Known Limitations

1. **PHP Version:** Requires PHP 8.1 or later
2. **Database:** Only MySQL/MariaDB supported (no PostgreSQL in this version)
3. **Architecture:** 64-bit systems only
4. **Web Servers:** Apache and Nginx only

## Support and Documentation

### Official Nextcloud Documentation
- [Admin Manual](https://docs.nextcloud.com/server/latest/admin_manual/)
- [User Manual](https://docs.nextcloud.com/server/latest/user_manual/)

### Community Resources
- [Nextcloud Forum](https://help.nextcloud.com/)
- [GitHub Issues](https://github.com/nextcloud/server/issues)

## License

This script is provided as-is for automated Nextcloud installation. Nextcloud itself is licensed under AGPLv3.

## Changelog

### Version 1.0
- Initial release with core features
- Separated file storage support
- IP address management tools
- Apache/Nginx support
- MariaDB/MySQL support
- Redis caching
- SSL/Let's Encrypt integration
- Helper scripts for management

## Contributing

Improvements and bug fixes are welcome. Please ensure any modifications maintain:
- No hardcoded values
- Secure password handling
- Proper error checking
- Clear user prompts
- Comprehensive logging

## Disclaimer

This script is provided for convenience. Always:
- Test in a non-production environment first
- Maintain regular backups
- Review security settings for your use case
- Keep systems updated
