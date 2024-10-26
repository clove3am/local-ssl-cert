#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Display help
show_help() {
    echo -e "${BLUE}Usage: ${0} [OPTIONS]${NC}"
    echo -e "Create or uninstall a local development SSL certificate."
    echo
    echo -e "${GREEN}Options:${NC}"
    echo "  -h, --help                Show this help message"
    echo "  -d, --domain DOMAIN       Set custom domain (default: localhost)"
    echo "  -o, --output-dir DIR      Set output directory (default: \${XDG_CONFIG_HOME}/local-certs)"
    echo "  -v, --valid-days DAYS     Set certificate validity in days (default: 365)"
    echo "  -i, --install             Install the root certificate system-wide"
    echo "  -u, --uninstall           Uninstall the root certificate"
    echo "  -p, --password PASS       Set PKCS12 export password (default: p12pass)"
    echo "  --country CODE            Set country code (default: US)"
    echo "  --state STATE             Set state/province (default: California)"
    echo "  --locality LOCALITY       Set locality/city (default: San Francisco)"
    echo "  --org ORGANIZATION        Set organization (default: Local Development)"
    echo "  --org-unit UNIT           Set organizational unit (default: Development)"
    echo "  --email EMAIL             Set email address (default: dev@localhost)"
    echo
    echo -e "${YELLOW}Example:${NC}"
    echo "  ${0} --domain mysite.local --install"
    echo "  ${0} --uninstall"
    exit 0
}

# Setup XDG directories
setup_xdg_dirs() {
    # Set XDG_CONFIG_HOME if not already set
    if [ -z "${XDG_CONFIG_HOME}" ]; then
        XDG_CONFIG_HOME="${HOME}/.config"
    fi

    # Create base directory for certificates
    DEFAULT_CERT_DIR="${XDG_CONFIG_HOME}/local-certs"

    # Create necessary directory
    mkdir -p "${DEFAULT_CERT_DIR}"
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=${NAME}
    elif [ -f /etc/debian_version ]; then
        OS="Debian"
    elif [ -f /etc/redhat-release ]; then
        OS="RedHat"
    else
        OS="Unknown"
    fi
}

# Install certificate
install_certificate() {
    detect_os
    echo -e "${BLUE}Detected OS: ${OS}${NC}"

    if [[ "${OS}" == *"Ubuntu"* ]] || [[ "${OS}" == *"Debian"* ]] || [[ "${OS}" == *"Linux Mint"* ]]; then
        echo -e "${GREEN}Installing certificate for Ubuntu/Debian...${NC}"
        sudo cp "${OUTPUT_DIR}/rootCA.pem" /usr/local/share/ca-certificates/rootCA.crt
        sudo update-ca-certificates

    elif [[ "${OS}" == *"Fedora"* ]] || [[ "${OS}" == *"RedHat"* ]] || [[ "${OS}" == *"CentOS"* ]]; then
        echo -e "${GREEN}Installing certificate for Fedora/RedHat/CentOS...${NC}"
        sudo cp "${OUTPUT_DIR}/rootCA.pem" /etc/pki/ca-trust/source/anchors/
        sudo update-ca-trust extract

    else
        echo -e "${RED}Warning: Automatic installation not supported for your OS (${OS})${NC}"
        echo -e "${YELLOW}Please manually install the root certificate (${OUTPUT_DIR}/rootCA.pem)${NC}"
    fi
}

# Uninstall certificate
uninstall_certificate() {
    detect_os
    echo -e "${BLUE}Detected OS: ${OS}${NC}"

    if [[ "${OS}" == *"Ubuntu"* ]] || [[ "${OS}" == *"Debian"* ]] || [[ "${OS}" == *"Linux Mint"* ]]; then
        echo -e "${GREEN}Uninstalling certificate for Ubuntu/Debian...${NC}"
        sudo rm -f /usr/local/share/ca-certificates/rootCA.crt
        sudo update-ca-certificates --fresh

    elif [[ "${OS}" == *"Fedora"* ]] || [[ "${OS}" == *"RedHat"* ]] || [[ "${OS}" == *"CentOS"* ]]; then
        echo -e "${GREEN}Uninstalling certificate for Fedora/RedHat/CentOS...${NC}"
        sudo rm -f /etc/pki/ca-trust/source/anchors/rootCA.pem
        sudo update-ca-trust extract

    else
        echo -e "${RED}Warning: Automatic uninstallation not supported for your OS (${OS})${NC}"
        echo -e "${YELLOW}Please manually remove the root certificate from your system's certificate store${NC}"
    fi
}

# Create certificate
create_certificate() {
    echo -e "${BLUE}Creating certificates...${NC}"

    # Generate RSA private key
    openssl genrsa -out "${OUTPUT_DIR}/rootCA.key" 2048

    # Generate root certificate
    openssl req -x509 -new -nodes -key "${OUTPUT_DIR}/rootCA.key" -sha256 -days ${DAYS_VALID} -out "${OUTPUT_DIR}/rootCA.pem" \
        -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${DOMAIN}/emailAddress=${EMAIL}"

    # Generate private key for domain
    openssl genrsa -out "${OUTPUT_DIR}/${DOMAIN}.key" 2048

    # Create certificate signing request (CSR)
    openssl req -new -sha256 \
        -key "${OUTPUT_DIR}/${DOMAIN}.key" \
        -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${DOMAIN}/emailAddress=${EMAIL}" \
        -out "${OUTPUT_DIR}/${DOMAIN}.csr"

    # Create certificate configuration file
    cat >"${OUTPUT_DIR}/${DOMAIN}.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
DNS.3 = localhost
DNS.4 = 127.0.0.1
EOF

    # Generate SSL certificate
    openssl x509 -req -in "${OUTPUT_DIR}/${DOMAIN}.csr" \
        -CA "${OUTPUT_DIR}/rootCA.pem" \
        -CAkey "${OUTPUT_DIR}/rootCA.key" \
        -CAcreateserial \
        -out "${OUTPUT_DIR}/${DOMAIN}.crt" \
        -days ${DAYS_VALID} \
        -sha256 \
        -extfile "${OUTPUT_DIR}/${DOMAIN}.ext"

    # Create combined PEM file
    cat "${OUTPUT_DIR}/${DOMAIN}.crt" "${OUTPUT_DIR}/rootCA.pem" >"${OUTPUT_DIR}/${DOMAIN}.pem"

    # Create PKCS12 file for browser import
    echo -e "${BLUE}Creating PKCS12 file for browser import...${NC}"
    openssl pkcs12 -export \
        -inkey "${OUTPUT_DIR}/${DOMAIN}.key" \
        -in "${OUTPUT_DIR}/${DOMAIN}.crt" \
        -certfile "${OUTPUT_DIR}/rootCA.pem" \
        -out "${OUTPUT_DIR}/${DOMAIN}.p12" \
        -passout "pass:${P12_PASSWORD}"

    # Set appropriate permissions
    chmod 600 "${OUTPUT_DIR}"/*.key "${OUTPUT_DIR}"/*.p12
    chmod 644 "${OUTPUT_DIR}"/*.crt "${OUTPUT_DIR}"/*.pem

    # Clean up temporary files
    rm -f "${OUTPUT_DIR}/${DOMAIN}.csr" "${OUTPUT_DIR}/${DOMAIN}.ext"

    echo -e "${GREEN}Certificate creation complete!${NC}"
    echo -e "${BLUE}Generated files are in: ${OUTPUT_DIR}${NC}"
}

# Setup XDG directories
setup_xdg_dirs

# Set default variables
DOMAIN="localhost"
DAYS_VALID=365
OUTPUT_DIR="${DEFAULT_CERT_DIR}"
COUNTRY="US"
STATE="California"
LOCALITY="San Francisco"
ORGANIZATION="Local Development"
ORGANIZATIONAL_UNIT="Development"
EMAIL="dev@localhost"
INSTALL=false
UNINSTALL=false
P12_PASSWORD="p12pass"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    -h | --help)
        show_help
        ;;
    -d | --domain)
        DOMAIN="$2"
        shift 2
        ;;
    -o | --output-dir)
        OUTPUT_DIR="$2"
        shift 2
        ;;
    -v | --valid-days)
        DAYS_VALID="$2"
        shift 2
        ;;
    -i | --install)
        INSTALL=true
        shift
        ;;
    -u | --uninstall)
        UNINSTALL=true
        shift
        ;;
    -p | --password)
        P12_PASSWORD="$2"
        shift 2
        ;;
    --country)
        COUNTRY="$2"
        shift 2
        ;;
    --state)
        STATE="$2"
        shift 2
        ;;
    --locality)
        LOCALITY="$2"
        shift 2
        ;;
    --org)
        ORGANIZATION="$2"
        shift 2
        ;;
    --org-unit)
        ORGANIZATIONAL_UNIT="$2"
        shift 2
        ;;
    --email)
        EMAIL="$2"
        shift 2
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        show_help
        ;;
    esac
done

# Handle uninstall
if [ "${UNINSTALL}" = true ]; then
    uninstall_certificate
    exit 0
fi

# Create certificate
create_certificate

# Install certificate if requested
if [ "${INSTALL}" = true ]; then
    install_certificate
fi

# Print helpful next steps
echo
echo -e "${GREEN}Next steps:${NC}"
if [ "${INSTALL}" = false ]; then
    echo -e "${YELLOW}1. To install the certificate system-wide, run this script with the --install option${NC}"
fi
echo -e "${BLUE}2. Use these files in your development environment:${NC}"
echo "   - Private key: ${OUTPUT_DIR}/${DOMAIN}.key"
echo "   - Certificate: ${OUTPUT_DIR}/${DOMAIN}.crt"
echo "   - Combined PEM: ${OUTPUT_DIR}/${DOMAIN}.pem"
echo "   - PKCS12 file: ${OUTPUT_DIR}/${DOMAIN}.p12 (password: ${P12_PASSWORD})"
echo
echo -e "${GREEN}For browsers:${NC}"
echo -e "${YELLOW}Import the ${DOMAIN}.p12 file:${NC}"
echo "- Chrome: Settings > Privacy and security > Security > Manage certificates > Import"
echo "- Firefox: Preferences > Privacy & Security > View Certificates > Import"
