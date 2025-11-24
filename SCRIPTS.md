# Nextcloud Installation Scripts - Complete Inventory

## Main Installation
- **`install_nextcloud.sh`** - Complete Nextcloud installation with all features

## Diagnostic Tools
- **`nextcloud-diagnostic.sh`** - Comprehensive system diagnostic tool
- **`quick_error_check.sh`** - Quick error identification tool
- **`test_db_connection.sh`** - Database connectivity test

## Fix Scripts

### General Fixes
- **`fix_internal_error.sh`** - Comprehensive Internal Server Error fix
- **`fix_permissions.sh`** - Quick permissions fix (most common issue)

### Nginx Specific
- **`fix_nginx_config.sh`** - Complete Nginx reconfiguration
- **`quick_nginx_fix.sh`** - Fix duplicate directive errors

## Helper Scripts (Created by install_nextcloud.sh)
These are installed to `/usr/local/bin/` during installation:
- **`nextcloud-add-ip`** - Add trusted domain/IP
- **`nextcloud-remove-ip`** - Remove trusted domain
- **`nextcloud-list-ips`** - List all trusted domains
- **`nextcloud-backup`** - Create backup
- **`nextcloud-info`** - Display system information

## Usage Order

### For Fresh Installation:
1. `test_db_connection.sh` (optional)
2. `install_nextcloud.sh`

### For Troubleshooting:
1. `quick_error_check.sh` - Identify the problem
2. `fix_permissions.sh` - Try quick fix first
3. `fix_internal_error.sh` - Comprehensive fix if needed

### For Nginx Issues:
1. `quick_nginx_fix.sh` - For duplicate directive errors
2. `fix_nginx_config.sh` - For complete reconfiguration

## Common Commands

```bash
# Make all scripts executable
chmod +x *.sh

# Run installation
sudo ./install_nextcloud.sh

# Quick error check
sudo ./quick_error_check.sh

# Fix permissions (most common fix)
sudo ./fix_permissions.sh

# Comprehensive error fix
sudo ./fix_internal_error.sh

# Fix Nginx issues
sudo ./quick_nginx_fix.sh
# or
sudo ./fix_nginx_config.sh
```

## Documentation
- **`README.md`** - Complete documentation
- **`QUICKSTART.md`** - Quick reference guide
- **`SCRIPTS.md`** - This file

## All Scripts Status
All scripts have been tested for syntax errors and are ready to use.
