#!/bin/bash

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file path
LOG_FILE="/var/log/change_fqdn.log"
rm -f "$LOG_FILE"  # Clear previous logs

# Function to log messages
log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Function to show progress messages
show_progress() {
    echo -e "${GREEN}$1${NC}"
}

# Function to check if user is root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root.${NC}"
        exit 1
    fi
}

# Get new FQDN from the user
get_new_fqdn() {
    current_fqdns=(/var/www/*)
    echo -e "${YELLOW}Available domains:${NC}"
    for i in "${!current_fqdns[@]}"; do
        echo "$((i + 1)). $(basename "${current_fqdns[$i]}")"
    done

    while true; do
        read -p "Select the domain to rename by number: " domain_index
        if [[ "$domain_index" =~ ^[0-9]+$ ]] && ((domain_index > 0 && domain_index <= ${#current_fqdns[@]})); then
            old_fqdn=$(basename "${current_fqdns[$((domain_index - 1))]}")
            break
        else
            echo -e "${RED}Invalid selection. Please choose a valid number from the list.${NC}"
        fi
    done

    while true; do
        read -p "Enter the new Fully Qualified Domain Name (e.g., itflow.domain.com): " new_fqdn
        if [[ $new_fqdn =~ ^([a-zA-Z0-9](-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}$ ]]; then
            echo -e "${GREEN}Domain will be changed from $old_fqdn to $new_fqdn${NC}"
            break
        else
            echo -e "${RED}Invalid domain. Please enter a valid Fully Qualified Domain Name.${NC}"
        fi
    done
}

# Update Apache configuration
update_apache() {
    log "Updating Apache configuration for $new_fqdn"
    show_progress "Updating Apache configuration..."

    apache_conf="/etc/apache2/sites-available/${new_fqdn}.conf"

    apache_config_content="<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName ${new_fqdn}
    DocumentRoot /var/www/${new_fqdn}
    ErrorLog \\\${APACHE_LOG_DIR}/error.log
    CustomLog \\\${APACHE_LOG_DIR}/access.log combined
</VirtualHost>"

    echo "$apache_config_content" > "$apache_conf"

    a2ensite ${new_fqdn}.conf >> "$LOG_FILE" 2>&1
    a2dissite ${old_fqdn}.conf >> "$LOG_FILE" 2>&1
    systemctl restart apache2 >> "$LOG_FILE" 2>&1

    echo -e "${GREEN}Apache configuration updated.${NC}"
}

# Rename webroot
rename_webroot() {
    log "Renaming webroot from $old_fqdn to $new_fqdn"
    show_progress "Renaming webroot..."

    mv "/var/www/${old_fqdn}" "/var/www/${new_fqdn}" >> "$LOG_FILE" 2>&1
    chown -R www-data:www-data "/var/www/${new_fqdn}"

    echo -e "${GREEN}Webroot renamed to /var/www/${new_fqdn}.${NC}"
}

# Update config.php
update_config_file() {
    log "Updating config.php for $new_fqdn"
    show_progress "Updating config.php..."

    config_file="/var/www/${new_fqdn}/config.php"
    if [[ -f "$config_file" ]]; then
        sed -i "s|\$config_base_url = '.*';|\$config_base_url = '${new_fqdn}';|" "$config_file"
        echo -e "${GREEN}config.php updated with new domain.${NC}"
    else
        echo -e "${RED}config.php not found in /var/www/${new_fqdn}.${NC}"
    fi
}

# Obtain SSL certificate
obtain_ssl_certificate() {
    log "Obtaining SSL certificate for $new_fqdn"
    show_progress "Obtaining SSL certificate..."

    certbot --apache --non-interactive --agree-tos --register-unsafely-without-email --domains "$new_fqdn" >> "$LOG_FILE" 2>&1

    echo -e "${GREEN}SSL certificate obtained.${NC}"
}

# Main execution
clear
echo -e "${GREEN}#############################################${NC}"
echo -e "${GREEN}# Change FQDN Script for ITFlow             #${NC}"
echo -e "${GREEN}#############################################${NC}"
echo

check_root
get_new_fqdn
update_apache
rename_webroot
update_config_file
obtain_ssl_certificate

log "FQDN updated successfully from $old_fqdn to $new_fqdn"
echo -e "${GREEN}FQDN updated successfully from $old_fqdn to $new_fqdn!${NC}"
