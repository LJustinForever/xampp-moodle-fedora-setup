#!/bin/bash

#===============================================================================
# XAMPP + Moodle Installer/Uninstaller for Fedora
# Run with: sudo ./setup-xampp-moodle.sh install
# Uninstall: sudo ./setup-xampp-moodle.sh uninstall
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
XAMPP_VERSION="8.1.25"
XAMPP_INSTALLER="xampp-linux-x64-${XAMPP_VERSION}-0-installer.run"
# Use Apache Friends CDN (faster and more reliable than SourceForge)
XAMPP_CDN_URL="https://downloadsapachefriends.global.ssl.fastly.net/xampp-files/${XAMPP_VERSION}/xampp-linux-x64-${XAMPP_VERSION}-0-installer.run"
XAMPP_SF_URL="https://sourceforge.net/projects/xampp/files/XAMPP%20Linux/${XAMPP_VERSION}/xampp-linux-x64-${XAMPP_VERSION}-0-installer.run/download"
XAMPP_DIR="/opt/lampp"
MOODLE_VERSION="401"
MOODLE_URL="https://download.moodle.org/download.php/direct/stable${MOODLE_VERSION}/moodle-latest-${MOODLE_VERSION}.tgz"
MOODLE_DIR="${XAMPP_DIR}/htdocs/moodle"
MOODLEDATA_DIR="/opt/lampp/moodledata"
DB_NAME="moodle"
DB_USER="moodleuser"
DB_PASS="MoodlePass123!"
BACKUP_FILE="/tmp/xampp_moodle_backup_info.txt"

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║        XAMPP + Moodle Installer for Fedora                    ║"
    echo "║                                                               ║"
    echo "║  Usage: sudo setup-xampp-moodle.sh [install|uninstall]        ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        log_warn "This script is designed for Fedora. Proceed with caution on other distros."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

install_dependencies() {
    log_info "Installing required dependencies..."
    dnf install -y wget tar libnsl net-tools curl perl 2>/dev/null || {
        log_warn "Some packages may already be installed or unavailable"
    }
}

check_file_valid() {
    local file="$1"
    local min_size="$2"
    
    if [[ -f "${file}" ]]; then
        local size=$(stat -c%s "${file}" 2>/dev/null || echo "0")
        if [[ ${size} -gt ${min_size} ]]; then
            return 0
        fi
    fi
    return 1
}

download_xampp() {
    log_info "Downloading XAMPP ${XAMPP_VERSION}..."
    
    cd /tmp
    
    # Check if already downloaded
    if check_file_valid "${XAMPP_INSTALLER}" 100000000; then
        log_info "XAMPP installer already downloaded, skipping..."
        chmod +x "${XAMPP_INSTALLER}"
        return 0
    fi
    
    rm -f xampp-linux-x64-*.run 2>/dev/null
    
    # Array of versions to try
    declare -a VERSIONS=("8.1.25" "8.0.30")
    
    for version in "${VERSIONS[@]}"; do
        local installer="xampp-linux-x64-${version}-0-installer.run"
        local cdn_url="https://downloadsapachefriends.global.ssl.fastly.net/xampp-files/${version}/${installer}"
        local sf_url="https://sourceforge.net/projects/xampp/files/XAMPP%20Linux/${version}/${installer}/download"
        
        log_info "Trying XAMPP ${version} from Apache Friends CDN..."
        
        # Try Apache Friends CDN first (faster)
        if curl -L -o "${installer}" "${cdn_url}" \
            --progress-bar \
            --connect-timeout 30 \
            --max-time 900 \
            --retry 3 \
            --retry-delay 5 \
            -f 2>/dev/null; then
            
            if check_file_valid "${installer}" 100000000; then
                XAMPP_VERSION="${version}"
                XAMPP_INSTALLER="${installer}"
                log_info "Downloaded from CDN: $(stat -c%s "${installer}" | numfmt --to=iec)"
                chmod +x "${XAMPP_INSTALLER}"
                return 0
            fi
        fi
        
        log_warn "CDN download failed, trying SourceForge..."
        rm -f "${installer}" 2>/dev/null
        
        # Try SourceForge as fallback
        if wget -O "${installer}" "${sf_url}" \
            --progress=bar:force \
            --timeout=30 \
            --tries=3 \
            --content-disposition 2>&1; then
            
            if check_file_valid "${installer}" 100000000; then
                XAMPP_VERSION="${version}"
                XAMPP_INSTALLER="${installer}"
                log_info "Downloaded from SourceForge: $(stat -c%s "${installer}" | numfmt --to=iec)"
                chmod +x "${XAMPP_INSTALLER}"
                return 0
            fi
        fi
        
        log_warn "Version ${version} download failed, trying next..."
        rm -f "${installer}" 2>/dev/null
    done
    
    # If all automatic downloads fail, provide manual instructions
    log_error "Automatic download failed."
    log_error ""
    log_error "Please download XAMPP manually:"
    log_error "1. Visit: https://www.apachefriends.org/download.html"
    log_error "2. Click 'XAMPP for Linux' -> Download (64-bit)"
    log_error "3. Save it to: /tmp/xampp-linux-x64-8.2.12-0-installer.run"
    log_error "4. Run: chmod +x /tmp/xampp-linux-x64-8.2.12-0-installer.run"
    log_error "5. Run this script again"
    exit 1
}

install_xampp() {
    log_info "Installing XAMPP..."
    
    if [[ -d "${XAMPP_DIR}" ]]; then
        # Check if it's a valid installation (lampp binary exists)
        if [[ -f "${XAMPP_DIR}/lampp" ]]; then
            log_warn "XAMPP is already installed at ${XAMPP_DIR}"
            read -p "Remove existing installation and reinstall? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                ${XAMPP_DIR}/lampp stop 2>/dev/null || true
                rm -rf ${XAMPP_DIR}
            else
                log_info "Using existing XAMPP installation..."
                return 0
            fi
        else
            log_warn "Found incomplete XAMPP directory, removing..."
            rm -rf ${XAMPP_DIR}
        fi
    fi
    
    cd /tmp
    ./${XAMPP_INSTALLER} --mode unattended
    
    log_info "XAMPP installed successfully!"
}

configure_xampp() {
    log_info "Configuring XAMPP..."
    
    # Start XAMPP
    ${XAMPP_DIR}/lampp start
    
    # Wait for MySQL to be ready
    log_info "Waiting for MySQL to start..."
    sleep 5
    
    # Increase PHP limits for Moodle
    PHP_INI="${XAMPP_DIR}/etc/php.ini"
    if [[ -f "${PHP_INI}" ]]; then
        log_info "Configuring PHP settings for Moodle..."
        
        # Backup original php.ini
        cp "${PHP_INI}" "${PHP_INI}.backup"
        
        # Update PHP settings
        sed -i 's/^memory_limit = .*/memory_limit = 256M/' "${PHP_INI}"
        sed -i 's/^post_max_size = .*/post_max_size = 100M/' "${PHP_INI}"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "${PHP_INI}"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "${PHP_INI}"
        sed -i 's/^max_input_time = .*/max_input_time = 300/' "${PHP_INI}"
        sed -i 's/^;max_input_vars = .*/max_input_vars = 5000/' "${PHP_INI}"
        sed -i 's/^max_input_vars = .*/max_input_vars = 5000/' "${PHP_INI}"
        
        # Enable required extensions
        sed -i 's/^;extension=intl/extension=intl/' "${PHP_INI}"
        sed -i 's/^;extension=soap/extension=soap/' "${PHP_INI}"
        sed -i 's/^;extension=sodium/extension=sodium/' "${PHP_INI}"
        sed -i 's/^;extension=gd/extension=gd/' "${PHP_INI}"
        sed -i 's/^;extension=zip/extension=zip/' "${PHP_INI}"
        
        # Enable OPcache for better performance
        sed -i 's/^;opcache.enable=.*/opcache.enable=1/' "${PHP_INI}"
        sed -i 's/^opcache.enable=.*/opcache.enable=1/' "${PHP_INI}"
        sed -i 's/^;opcache.memory_consumption=.*/opcache.memory_consumption=128/' "${PHP_INI}"
        sed -i 's/^;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' "${PHP_INI}"
        sed -i 's/^;zend_extension=opcache/zend_extension=opcache/' "${PHP_INI}"
    fi
    
    # Restart to apply PHP changes
    ${XAMPP_DIR}/lampp restart
    sleep 3
}

download_moodle() {
    log_info "Downloading Moodle..."
    
    cd /tmp
    
    declare -a MOODLE_VERSIONS=("401" "400")
    
    for ver in "${MOODLE_VERSIONS[@]}"; do
        local file="moodle-latest-${ver}.tgz"
        
        # Check if already downloaded
        if check_file_valid "${file}" 50000000; then
            log_info "Moodle archive already downloaded, skipping..."
            MOODLE_VERSION="${ver}"
            return 0
        fi
    done
    
    for ver in "${MOODLE_VERSIONS[@]}"; do
        local file="moodle-latest-${ver}.tgz"
        local url="https://download.moodle.org/download.php/direct/stable${ver}/moodle-latest-${ver}.tgz"
        
        log_info "Trying Moodle ${ver}..."
        
        if curl -L -o "${file}" "${url}" \
            --progress-bar \
            --connect-timeout 30 \
            --max-time 600 \
            --retry 3 \
            -f 2>/dev/null; then
            
            if check_file_valid "${file}" 50000000; then
                MOODLE_VERSION="${ver}"
                log_info "Downloaded Moodle: $(stat -c%s "${file}" | numfmt --to=iec)"
                return 0
            fi
        fi
        
        rm -f "${file}" 2>/dev/null
        log_warn "Moodle ${ver} download failed, trying next..."
    done
    
    log_error "Failed to download Moodle. Please check your internet connection."
    exit 1
}

install_moodle() {
    log_info "Installing Moodle..."
    
    # Remove existing Moodle installation if present
    if [[ -d "${MOODLE_DIR}" ]]; then
        log_warn "Existing Moodle installation found. Removing..."
        rm -rf "${MOODLE_DIR}"
    fi
    
    # Extract Moodle
    cd /tmp
    tar -xzf "moodle-latest-${MOODLE_VERSION}.tgz" -C "${XAMPP_DIR}/htdocs/"
    
    # Create moodledata directory
    log_info "Creating Moodle data directory..."
    mkdir -p "${MOODLEDATA_DIR}"
    
    # Set permissions
    log_info "Setting permissions..."
    chown -R daemon:daemon "${MOODLE_DIR}"
    chown -R daemon:daemon "${MOODLEDATA_DIR}"
    chmod -R 755 "${MOODLE_DIR}"
    chmod -R 777 "${MOODLEDATA_DIR}"
    
    log_info "Moodle files installed successfully!"
}

setup_database() {
    log_info "Setting up MySQL database for Moodle..."
    
    MYSQL="${XAMPP_DIR}/bin/mysql"
    
    # Create database and user
    ${MYSQL} -u root <<EOF
DROP DATABASE IF EXISTS ${DB_NAME};
CREATE DATABASE ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS '${DB_USER}'@'localhost';
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    log_info "Database '${DB_NAME}' created with user '${DB_USER}'"
}

configure_selinux() {
    log_info "Configuring SELinux (if enabled)..."
    
    if command -v getenforce &> /dev/null; then
        if [[ $(getenforce) != "Disabled" ]]; then
            log_warn "SELinux is enabled. Setting permissive mode for XAMPP directories..."
            setsebool -P httpd_unified 1 2>/dev/null || true
            semanage fcontext -a -t httpd_sys_rw_content_t "${MOODLEDATA_DIR}(/.*)?" 2>/dev/null || true
            restorecon -Rv "${MOODLEDATA_DIR}" 2>/dev/null || true
        fi
    fi
}

configure_firewall() {
    log_info "Configuring firewall..."
    
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=http 2>/dev/null || true
        firewall-cmd --permanent --add-service=https 2>/dev/null || true
        firewall-cmd --permanent --add-port=80/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=443/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        log_info "Firewall configured for HTTP/HTTPS"
    fi
}

create_systemd_service() {
    log_info "Creating systemd service for XAMPP..."
    
    cat > /etc/systemd/system/xampp.service <<EOF
[Unit]
Description=XAMPP Server
After=network.target

[Service]
Type=forking
ExecStart=${XAMPP_DIR}/lampp start
ExecStop=${XAMPP_DIR}/lampp stop
ExecReload=${XAMPP_DIR}/lampp reload
PIDFile=/opt/lampp/logs/httpd.pid
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable xampp.service
    
    log_info "XAMPP systemd service created and enabled"
}

save_install_info() {
    log_info "Saving installation info..."
    
    cat > "${BACKUP_FILE}" <<EOF
XAMPP_VERSION=${XAMPP_VERSION}
MOODLE_VERSION=${MOODLE_VERSION}
XAMPP_DIR=${XAMPP_DIR}
MOODLE_DIR=${MOODLE_DIR}
MOODLEDATA_DIR=${MOODLEDATA_DIR}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
INSTALL_DATE=$(date)
EOF
    
    chmod 600 "${BACKUP_FILE}"
}

print_success() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           INSTALLATION COMPLETED SUCCESSFULLY!                ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Access Moodle at:${NC} http://localhost/moodle"
    echo ""
    echo -e "${YELLOW}Moodle Setup Configuration:${NC}"
    echo "  • Database Type:     MariaDB (native/mariadb)"
    echo "  • Database Host:     localhost"
    echo "  • Database Name:     ${DB_NAME}"
    echo "  • Database User:     ${DB_USER}"
    echo "  • Database Password: ${DB_PASS}"
    echo "  • Tables Prefix:     mdl_"
    echo "  • Data Directory:    ${MOODLEDATA_DIR}"
    echo ""
    echo -e "${BLUE}XAMPP Control:${NC}"
    echo "  • Start:   sudo ${XAMPP_DIR}/lampp start"
    echo "  • Stop:    sudo ${XAMPP_DIR}/lampp stop"
    echo "  • Status:  sudo ${XAMPP_DIR}/lampp status"
    echo "  • Panel:   sudo ${XAMPP_DIR}/manager-linux-x64.run"
    echo ""
    echo -e "${BLUE}Systemd Service:${NC}"
    echo "  • sudo systemctl start xampp"
    echo "  • sudo systemctl stop xampp"
    echo "  • sudo systemctl status xampp"
    echo ""
    echo -e "${YELLOW}To uninstall:${NC} sudo setup-xampp-moodle.sh uninstall"
    echo ""
}

#===============================================================================
# UNINSTALL FUNCTIONS
#===============================================================================

uninstall_all() {
    log_info "Starting uninstallation process..."
    
    # Stop XAMPP
    log_info "Stopping XAMPP services..."
    ${XAMPP_DIR}/lampp stop 2>/dev/null || true
    systemctl stop xampp 2>/dev/null || true
    
    # Remove systemd service
    log_info "Removing systemd service..."
    systemctl disable xampp 2>/dev/null || true
    rm -f /etc/systemd/system/xampp.service
    systemctl daemon-reload
    
    # Remove Moodle data directory
    log_info "Removing Moodle data directory..."
    rm -rf "${MOODLEDATA_DIR}"
    
    # Remove XAMPP (includes Moodle in htdocs)
    log_info "Removing XAMPP installation..."
    if [[ -f "${XAMPP_DIR}/uninstall" ]]; then
        ${XAMPP_DIR}/uninstall --mode unattended 2>/dev/null || rm -rf ${XAMPP_DIR}
    else
        rm -rf ${XAMPP_DIR}
    fi
    
    # Remove downloaded files
    log_info "Cleaning up downloaded files..."
    rm -f /tmp/xampp-linux-x64-*.run
    rm -f /tmp/moodle-latest-*.tgz
    rm -f "${BACKUP_FILE}"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           UNINSTALLATION COMPLETED SUCCESSFULLY!              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}The following have been removed:${NC}"
    echo "  • XAMPP from ${XAMPP_DIR}"
    echo "  • Moodle from ${MOODLE_DIR}"
    echo "  • Moodle data from ${MOODLEDATA_DIR}"
    echo "  • XAMPP systemd service"
    echo "  • Downloaded installer files"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

main_install() {
    print_banner
    check_root
    check_fedora
    
    echo -e "${YELLOW}This script will install:${NC}"
    echo "  • XAMPP (Apache, MySQL/MariaDB, PHP, Perl)"
    echo "  • Moodle LMS (Latest Stable)"
    echo ""
    read -p "Continue with installation? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    install_dependencies
    download_xampp
    install_xampp
    configure_xampp
    download_moodle
    install_moodle
    setup_database
    configure_selinux
    configure_firewall
    create_systemd_service
    save_install_info
    
    # Final restart
    ${XAMPP_DIR}/lampp restart
    
    print_success
}

main_uninstall() {
    print_banner
    check_root
    
    echo -e "${RED}WARNING: This will remove XAMPP and Moodle completely!${NC}"
    echo "This includes:"
    echo "  • All XAMPP files and configurations"
    echo "  • All Moodle files and database"
    echo "  • All uploaded content in Moodle"
    echo ""
    read -p "Are you sure you want to uninstall? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    read -p "Type 'UNINSTALL' to confirm: " confirm
    if [[ "${confirm}" != "UNINSTALL" ]]; then
        log_error "Uninstall cancelled."
        exit 1
    fi
    
    uninstall_all
}

# Parse command line arguments
case "${1:-}" in
    install)
        main_install
        ;;
    uninstall|remove|undo)
        main_uninstall
        ;;
    *)
        print_banner
        echo "Usage: sudo setup-xampp-moodle.sh [install|uninstall]"
        echo ""
        echo "Commands:"
        echo "  install    - Install XAMPP and Moodle"
        echo "  uninstall  - Remove XAMPP and Moodle completely"
        echo ""
        exit 1
        ;;
esac
