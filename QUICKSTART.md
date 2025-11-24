# Nextcloud Installation Quick Start Guide

## Prerequisites Checklist
- [ ] Ubuntu 20.04+ or Debian 11+ server
- [ ] Root or sudo access
- [ ] Static IP or domain name
- [ ] Internet connection
- [ ] At least 2GB RAM (recommended)
- [ ] 20GB+ free disk space

## Quick Installation Steps

### 1. Download and Run
```bash
# Download the script
wget [script-location]/install_nextcloud.sh

# Make executable
chmod +x install_nextcloud.sh

# (Optional) Test database connection first
chmod +x test_db_connection.sh
./test_db_connection.sh

# Run as root
sudo ./install_nextcloud.sh
```

### 2. Answer Configuration Prompts

You'll be asked for:
1. **Web Server**: Apache (1) or Nginx (2)
2. **Database Type**: MariaDB (1) or MySQL (2)
3. **Database Name**: Default: `nextcloud`
4. **Database User**: Default: `nextcloud`
5. **Database Password**: Min 8 characters (no default)
6. **Database Root Password**: Min 8 characters (no default)
7. **Data Directory**: Default: `/mnt/nextcloud-data`
8. **Admin Username**: Default: `admin`
9. **Admin Password**: Min 8 characters (no default)
10. **Domain/IP**: Your server's domain or IP address
11. **SSL Setup**: Yes/No (optional)

### 3. Wait for Installation
The script will automatically:
- Install all required packages
- Configure the database
- Download latest Nextcloud
- Set up the web server
- Configure caching
- Create helper scripts

## Post-Installation

### Access Nextcloud
```
Browser: http://your-domain-or-ip
Login: Your admin username and password
```

### Essential Commands

**If your IP address changes:**
```bash
sudo nextcloud-add-ip NEW_IP_ADDRESS
```

**To see all trusted domains:**
```bash
sudo nextcloud-list-ips
```

**To check system info:**
```bash
sudo nextcloud-info
```

**To create a backup:**
```bash
sudo nextcloud-backup
```

## Important Locations

| Component | Location |
|-----------|----------|
| **Nextcloud Files** | `/var/www/nextcloud` |
| **User Data** | `/mnt/nextcloud-data` (or your custom location) |
| **Config File** | `/var/www/nextcloud/config/config.php` |
| **Log File** | `/mnt/nextcloud-data/nextcloud.log` |
| **Backup Location** | `/var/backups/nextcloud/` |

## Common Issues & Solutions

### Internal Server Error (500)

This is the most common issue. Try these fixes in order:

**Quick Fix #1 - Permissions (80% of cases)**
```bash
sudo ./fix_permissions.sh
```

**Quick Fix #2 - Check what's wrong**
```bash
sudo ./quick_error_check.sh
```

**Quick Fix #3 - Comprehensive repair**
```bash
sudo ./fix_internal_error.sh
```

**Manual fixes:**
```bash
# Fix ownership
sudo chown -R www-data:www-data /var/www/nextcloud
sudo chown -R www-data:www-data /mnt/nextcloud-data

# Restart services
sudo systemctl restart apache2  # or nginx
sudo systemctl restart mysql
sudo systemctl restart redis-server

# Run Nextcloud repair
sudo -u www-data php /var/www/nextcloud/occ maintenance:repair
```

### Nginx Configuration Error

**Problem:** "root" directive is duplicate error
```bash
# Quick fix for duplicate directive error:
sudo ./quick_nginx_fix.sh

# Or complete reconfiguration:
sudo ./fix_nginx_config.sh
```

**Problem:** sed: unknown option to 's' during installation
```bash
# This error occurs during Nginx setup
# The installation script has been fixed, but if you encounter it:

# Fix the Nginx configuration:
sudo ./fix_nginx_config.sh
```

### Can't Access After IP Change
```bash
# Add your new IP
sudo nextcloud-add-ip YOUR_NEW_IP

# Or add a domain
sudo nextcloud-add-ip yourdomain.com
```

### Forgot Admin Password
```bash
# Reset admin password
cd /var/www/nextcloud
sudo -u www-data php occ user:resetpassword admin
```

### Check Service Status
```bash
# Web server
sudo systemctl status apache2  # or nginx

# Database
sudo systemctl status mariadb  # or mysql

# Cache
sudo systemctl status redis-server

# PHP-FPM (Nginx only)
sudo systemctl status php8.2-fpm
```

### Emergency File Access
Your files are always accessible at the data directory:
```bash
cd /mnt/nextcloud-data/[username]/files/
```

## Security Checklist

After installation:
- [ ] Enable firewall (`ufw allow 80,443/tcp`)
- [ ] Set up SSL certificate (if not done during install)
- [ ] Regular backups (`sudo nextcloud-backup`)
- [ ] System updates (`apt update && apt upgrade`)
- [ ] Monitor logs regularly

## Need Help?

1. Check installation log: `/var/log/nextcloud_install_[timestamp].log`
2. Run system info: `sudo nextcloud-info`
3. Check Nextcloud status: `sudo -u www-data php /var/www/nextcloud/occ status`
4. Review the full README.md for detailed information

## Quick Tips

- **Performance**: The script automatically sets up Redis caching
- **Security**: All passwords must be 8+ characters
- **Flexibility**: Files stored separately for easy access
- **Recovery**: Use helper scripts for IP management
- **Backups**: Run `nextcloud-backup` regularly

---
**Script Version**: 1.0  
**Compatible OS**: Ubuntu 20.04+, Debian 11+  
**Support**: See README.md for full documentation
