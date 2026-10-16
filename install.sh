#!/usr/bin/env bash
# ==============================================================================
# DNSONE — Standalone Installer (Interactive SSL & Domain Setup)
# Works online & offline.
# Supported OS: Ubuntu 20.04+, Debian 11+, CentOS/RHEL/Alma/Rocky 8+
# ==============================================================================

set -e

# Terminal Colors & Styling
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

clear 2>/dev/null || true
echo -e "${CYAN}${BOLD}"
echo "  ██████╗ ███╗   ██╗███████╗ ██████╗ ███╗   ██╗███████╗"
echo "  ██╔══██╗████╗  ██║██╔════╝██╔═══██╗████╗  ██║██╔════╝"
echo "  ██║  ██║██╔██╗ ██║███████╗██║   ██║██╔██╗ ██║███████╗"
echo "  ██║  ██║██║╚██╗██║╚════██║██║   ██║██║╚██╗██║╚════██║"
echo "  ██████╔╝██║ ╚████║███████║╚██████╔╝██║ ╚████║███████║"
echo "  ╚═════╝ ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝"
echo -e "       ${PURPLE}⚡ Standalone Low-Latency SmartDNS & Anti-Sanction Gaming Gateway ⚡${NC}"
echo -e "       ${YELLOW}Package: ONLINE INSTALLER · Single Binary · Go 1.26 · OWASP Hardened${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[Error] Please run this installer as root (or use sudo).${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/hyperdns"

PUBLIC_IP=""
for _ip_ep in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com https://checkip.amazonaws.com; do
    _ip_val=$(curl -fsS --connect-timeout 3 --max-time 5 "${_ip_ep}" 2>/dev/null | tr -d '[:space:]')
    if [ -n "${_ip_val}" ]; then
        PUBLIC_IP="${_ip_val}"
        break
    fi
done
if [ -z "${PUBLIC_IP}" ]; then
    PUBLIC_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
if [ -z "${PUBLIC_IP}" ]; then
    PUBLIC_IP="YOUR_SERVER_IP"
fi

validate_domain() {
    case "$1" in
        *[!a-zA-Z0-9.-]* | .* | *. | *..* | -* | "" ) return 1 ;;
    esac
    case "$1" in
        *.*) return 0 ;;
        *)   return 1 ;;
    esac
}

validate_email() {
    case "$1" in
        *@*.*) return 0 ;;
        *) return 1 ;;
    esac
}

echo -e "${CYAN}${BOLD}[1/6] Downloading the latest DNSONE release binary...${NC}"

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64|amd64) BIN_ARCH="amd64" ;;
    aarch64|arm64) BIN_ARCH="arm64" ;;
    *)
        echo -e "${RED}[Error] Unsupported architecture: ${ARCH}${NC}"
        exit 1
        ;;
esac
echo -e "  ${GREEN}✓ Architecture detected: ${ARCH} (${BIN_ARCH})${NC}"

HYPERDNS_REF="${HYPERDNS_REF:-dnsone}"
RAW_BASE="https://raw.githubusercontent.com/iransinfo/DNSONE/${HYPERDNS_REF}"
RELEASE_BASE="https://github.com/iransinfo/DNSONE/releases/download/${HYPERDNS_REF}"

DL_BIN="$(mktemp /tmp/hyperdns-bin.XXXXXX)"
if curl -fL --retry 3 --connect-timeout 10 "${RELEASE_BASE}/hyperdns" -o "${DL_BIN}" 2>/dev/null || \
   curl -fL --retry 3 --connect-timeout 10 "${RELEASE_BASE}/hyperdns-linux-${BIN_ARCH}" -o "${DL_BIN}" 2>/dev/null; then
    chmod +x "${DL_BIN}"
    SRC_BIN="${DL_BIN}"
    echo -e "  ${GREEN}✓ Downloaded release binary (${BIN_ARCH}): $(( $(stat -c%s "${DL_BIN}" 2>/dev/null || echo 0) / 1024 / 1024 )) MB${NC}"
else
    echo -e "${YELLOW}[Notice] Release binary not found at GitHub Releases tag. Trying local fallback...${NC}"
    if [ -f "${SCRIPT_DIR}/../hyperdns" ]; then
        SRC_BIN="${SCRIPT_DIR}/../hyperdns"
    elif [ -f "/opt/hyperdns/hyperdns" ]; then
        SRC_BIN="/opt/hyperdns/hyperdns"
    else
        echo -e "${RED}[Error] Could not download the DNSONE binary from GitHub Releases.${NC}"
        exit 1
    fi
fi

ONLINE_CONFIG_EXAMPLE="$(mktemp /tmp/hyperdns-cfg.XXXXXX)"
curl -fsL --retry 3 "${RAW_BASE}/config.example.json" -o "${ONLINE_CONFIG_EXAMPLE}" || true

ONLINE_RESTORE="$(mktemp /tmp/hyperdns-restore.XXXXXX)"
curl -fsL --retry 3 "${RAW_BASE}/scripts/restore.sh" -o "${ONLINE_RESTORE}" || true

ONLINE_SSL_ISSUE="$(mktemp /tmp/hyperdns-ssl.XXXXXX)"
curl -fsL --retry 3 "${RAW_BASE}/scripts/ssl_issue.sh" -o "${ONLINE_SSL_ISSUE}" || true

ONLINE_VERSION_JSON="$(mktemp /tmp/hyperdns-ver.XXXXXX)"
curl -fsL --retry 3 "${RAW_BASE}/version.json" -o "${ONLINE_VERSION_JSON}" 2>/dev/null || true

install -d -o root -g root -m 0755 "${INSTALL_DIR}"
install -d -o root -g root -m 0700 "${INSTALL_DIR}/certs"

IS_UPGRADE=false
PREV_VERSION=""

if [ -f "${INSTALL_DIR}/hyperdns" ] || [ -f "${INSTALL_DIR}/config.json" ] || [ -f "${INSTALL_DIR}/data.db" ]; then
    IS_UPGRADE=true
    if [ -x "${INSTALL_DIR}/hyperdns" ]; then
        PREV_VERSION="$("${INSTALL_DIR}/hyperdns" -version 2>/dev/null | head -n1 || true)"
    fi
    [ -z "${PREV_VERSION}" ] && PREV_VERSION="unknown"

    if systemctl is-active --quiet hyperdns 2>/dev/null; then
        systemctl stop hyperdns || true
    fi

    ARCHIVE="/root/dnsone-preinstall-$(date +%Y%m%d_%H%M%S).tar.gz"
    tar czf "${ARCHIVE}" -C / opt/hyperdns 2>/dev/null || true
    chmod 600 "${ARCHIVE}" 2>/dev/null || true

    rm -rf "${INSTALL_DIR}"
fi

install -d -o root -g root -m 0755 "${INSTALL_DIR}"
install -d -o root -g root -m 0700 "${INSTALL_DIR}/certs"

cp -f "${SRC_BIN}" "${INSTALL_DIR}/hyperdns"
chmod +x "${INSTALL_DIR}/hyperdns"
ln -sf "${INSTALL_DIR}/hyperdns" /usr/local/bin/hdns

install -d -o root -g root -m 0755 "${INSTALL_DIR}/scripts"
if [ -f "${ONLINE_RESTORE}" ] && [ -s "${ONLINE_RESTORE}" ]; then
    install -o root -g root -m 0755 "${ONLINE_RESTORE}" "${INSTALL_DIR}/scripts/restore.sh"
fi
rm -f "${ONLINE_RESTORE}"

if [ -f "${ONLINE_SSL_ISSUE}" ] && [ -s "${ONLINE_SSL_ISSUE}" ]; then
    install -o root -g root -m 0755 "${ONLINE_SSL_ISSUE}" "${INSTALL_DIR}/scripts/ssl_issue.sh"
elif [ -f "${SCRIPT_DIR}/ssl_issue.sh" ]; then
    install -o root -g root -m 0755 "${SCRIPT_DIR}/ssl_issue.sh" "${INSTALL_DIR}/scripts/ssl_issue.sh"
fi
rm -f "${ONLINE_SSL_ISSUE}"

if [ -f "${ONLINE_VERSION_JSON}" ] && [ -s "${ONLINE_VERSION_JSON}" ]; then
    cp -f "${ONLINE_VERSION_JSON}" "${INSTALL_DIR}/version.json"
fi

FRESH_CONFIG_SOURCE=""
if [ -f "${ONLINE_CONFIG_EXAMPLE}" ] && [ -s "${ONLINE_CONFIG_EXAMPLE}" ]; then
    FRESH_CONFIG_SOURCE="${ONLINE_CONFIG_EXAMPLE}"
elif [ -f "${SCRIPT_DIR}/../config.example.json" ]; then
    FRESH_CONFIG_SOURCE="${SCRIPT_DIR}/../config.example.json"
fi

GENERATED_ADMIN_PASSWORD="$(openssl rand -hex 6 2>/dev/null || head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 12)"
PANEL_PORT="$(shuf -i 20000-60000 -n 1 2>/dev/null || awk 'BEGIN{srand();print int(20000+rand()*40000)}')"

if [ -n "${FRESH_CONFIG_SOURCE}" ]; then
    cp -f "${FRESH_CONFIG_SOURCE}" "${INSTALL_DIR}/config.json"
    GENERATED_API_KEY="$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)"
    
    sed -i "s|\"admin_password\": \"[^\"]*\"|\"admin_password\": \"${GENERATED_ADMIN_PASSWORD}\"|" "${INSTALL_DIR}/config.json"
    sed -i "s|\"api_key\": \"[^\"]*\"|\"api_key\": \"${GENERATED_API_KEY}\"|" "${INSTALL_DIR}/config.json"
    sed -i "s|\"web_port\": [0-9]*|\"web_port\": ${PANEL_PORT}|" "${INSTALL_DIR}/config.json"
fi

if [ -f "${INSTALL_DIR}/config.json" ]; then
    chmod 600 "${INSTALL_DIR}/config.json" 2>/dev/null || true
fi

echo -e "  ${GREEN}✓ Binary installed to ${INSTALL_DIR}/hyperdns${NC}"
echo -e "  ${GREEN}✓ Global CLI command installed: 'hdns'${NC}"

# ==============================================================================
# STEP 2: RESOLVE PORT 53 CONFLICTS (SYSTEMD-RESOLVED)
# ==============================================================================
echo -e "${CYAN}${BOLD}[2/6] Freeing Port 53 (systemd-resolved resolver)...${NC}"
if systemctl is-active --quiet systemd-resolved; then
    mkdir -p /etc/systemd/resolved.conf.d/
    cat << 'EOF' > /etc/systemd/resolved.conf.d/hyperdns.conf
[Resolve]
DNSStubListener=no
EOF
    chmod 755 /etc/systemd/resolved.conf.d
    chmod 644 /etc/systemd/resolved.conf.d/hyperdns.conf
    systemctl restart systemd-resolved || true

    RESOLV_MARKER="${INSTALL_DIR}/.resolv-backup"
    if [ ! -f "${RESOLV_MARKER}" ]; then
        if [ -L /etc/resolv.conf ]; then
            printf 'symlink\n%s\n' "$(readlink /etc/resolv.conf)" > "${RESOLV_MARKER}"
        elif [ -f /etc/resolv.conf ]; then
            { printf 'file\n'; cat /etc/resolv.conf; } > "${RESOLV_MARKER}"
        else
            printf 'absent\n' > "${RESOLV_MARKER}"
        fi
        chmod 600 "${RESOLV_MARKER}" 2>/dev/null || true
    fi
    rm -f /etc/resolv.conf
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\noptions timeout:2 attempts:2\n' > /etc/resolv.conf
    echo -e "  ${GREEN}✓ Port 53 released successfully!${NC}"
else
    echo -e "  ${GREEN}✓ Port 53 is clear.${NC}"
fi

# ==============================================================================
# STEP 3: FIREWALL RULES CONFIGURATION
# ==============================================================================
echo -e "${CYAN}${BOLD}[3/6] Configuring Firewall Rules...${NC}"
PORTS=(53 80 443 853 2099 5222 5223 8393 8443)
if [ -n "${PANEL_PORT:-}" ] && [ "${PANEL_PORT}" != "8080" ]; then
    PORTS+=("${PANEL_PORT}")
fi

if command -v ufw >/dev/null 2>&1; then
    UFW_ADDED="$(ufw show added 2>/dev/null || true)"
    for p in "${PORTS[@]}"; do
        if ! printf '%s\n' "${UFW_ADDED}" | grep -qxF "ufw allow ${p}"; then
            ufw allow "${p}" >/dev/null 2>&1 || true
        fi
    done
    echo -e "  ${GREEN}✓ UFW firewall rules configured.${NC}"
elif command -v firewall-cmd >/dev/null 2>&1; then
    for p in "${PORTS[@]}"; do
        for proto in tcp udp; do
            firewall-cmd --permanent --add-port="${p}/${proto}" >/dev/null 2>&1 || true
        done
    done
    firewall-cmd --reload >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓ Firewalld rules configured.${NC}"
fi

# ==============================================================================
# STEP 4: SYSTEMD SERVICE SETUP
# ==============================================================================
echo -e "${CYAN}${BOLD}[4/6] Creating Systemd Service...${NC}"
cat << 'EOF' > /etc/systemd/system/hyperdns.service
[Unit]
Description=DNSONE — Standalone SmartDNS & Gaming Gateway
Documentation=https://github.com/iransinfo/DNSONE
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/hyperdns
RuntimeDirectory=hyperdns
RuntimeDirectoryMode=0700

ExecStart=/opt/hyperdns/hyperdns -daemon \
    -config /opt/hyperdns/config.json \
    -db /opt/hyperdns/data.db \
    -key /opt/hyperdns/master.key

Restart=always
RestartSec=3s
TimeoutStopSec=15s
SyslogIdentifier=hyperdns
LimitNOFILE=65535
OOMPolicy=continue

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/hyperdns.service
systemctl daemon-reload
echo -e "  ${GREEN}✓ Systemd service configured.${NC}"

# ==============================================================================
# STEP 5: DOMAIN & SSL CONFIGURATION
# ==============================================================================
echo ""
echo -e "${CYAN}${BOLD}[5/6] Domain & SSL Certificate Setup...${NC}"

SETUP_DOMAIN=""
SETUP_EMAIL=""

# Check if terminal is interactive
if [ -t 0 ]; then
    read -rp "👉 Enter your Domain (e.g. dns.example.com) [Press Enter to skip]: " USER_DOMAIN
    if [ -n "${USER_DOMAIN}" ]; then
        if validate_domain "${USER_DOMAIN}"; then
            SETUP_DOMAIN="${USER_DOMAIN}"
            read -rp "👉 Enter your Email for Let's Encrypt SSL: " USER_EMAIL
            if validate_email "${USER_EMAIL}"; then
                SETUP_EMAIL="${USER_EMAIL}"
            else
                echo -e "  ${YELLOW}⚠ Invalid email format. SSL generation will be skipped.${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠ Invalid domain format. Skipping SSL setup.${NC}"
        fi
    fi
fi

SSL_ISSUED=false
if [ -n "${SETUP_DOMAIN}" ] && [ -n "${SETUP_EMAIL}" ]; then
    echo -e "  ${CYAN}Applying domain and email to /opt/hyperdns/config.json...${NC}"
    sed -i "s|\"domain\": \"[^\"]*\"|\"domain\": \"${SETUP_DOMAIN}\"|" "${INSTALL_DIR}/config.json"
    sed -i "s|\"email\": \"[^\"]*\"|\"email\": \"${SETUP_EMAIL}\"|" "${INSTALL_DIR}/config.json"
    sed -i "s|\"acme_email\": \"[^\"]*\"|\"acme_email\": \"${SETUP_EMAIL}\"|" "${INSTALL_DIR}/config.json"
    sed -i "s|\"ssl_enabled\": false|\"ssl_enabled\": true|" "${INSTALL_DIR}/config.json"

    # Issue SSL
    if [ -x "${INSTALL_DIR}/scripts/ssl_issue.sh" ]; then
        echo -e "  ${CYAN}Running SSL issuance script...${NC}"
        if "${INSTALL_DIR}/scripts/ssl_issue.sh" "${SETUP_DOMAIN}" "${SETUP_EMAIL}"; then
            SSL_ISSUED=true
            echo -e "  ${GREEN}✓ SSL certificate obtained successfully!${NC}"
        fi
    elif [ -x "${INSTALL_DIR}/hyperdns" ]; then
        echo -e "  ${CYAN}Issuing SSL via hyperdns CLI...${NC}"
        if "${INSTALL_DIR}/hyperdns" -issue-ssl -domain "${SETUP_DOMAIN}" -email "${SETUP_EMAIL}" 2>/dev/null; then
            SSL_ISSUED=true
            echo -e "  ${GREEN}✓ SSL certificate obtained successfully!${NC}"
        fi
    fi
fi

# ==============================================================================
# STEP 6: START & VERIFY SERVICE
# ==============================================================================
echo ""
echo -e "${CYAN}${BOLD}[6/6] Starting DNSONE Service...${NC}"
systemctl enable hyperdns >/dev/null 2>&1
systemctl restart hyperdns

sleep 2
if systemctl is-active --quiet hyperdns; then
    echo -e "  ${GREEN}✓ DNSONE Service is active and running!${NC}"
else
    echo -e "  ${RED}✗ Warning: Service failed to start. Check: journalctl -u hyperdns -n 50${NC}"
fi

# Summary Banner
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}       🎉 DNSONE INSTALLATION COMPLETED SUCCESSFULLY!                ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}👤 Default Username:${NC}       ${YELLOW}admin${NC}"
echo -e "  ${BOLD}🔑 Generated Password:${NC}     ${YELLOW}${GENERATED_ADMIN_PASSWORD}${NC}"
echo -e "  ${BOLD}📂 Config Location:${NC}        ${YELLOW}/opt/hyperdns/config.json${NC}"

if [ -n "${SETUP_DOMAIN}" ]; then
    echo -e "  ${BOLD}🌐 Admin Dashboard:${NC}        ${CYAN}https://${SETUP_DOMAIN}:${PANEL_PORT}/admin${NC}"
    echo -e "  ${BOLD}🔗 Subscription URL:${NC}       ${CYAN}https://${SETUP_DOMAIN}:${PANEL_PORT}/sub${NC}"
    echo -e "  ${BOLD}🛡️  DoT / DoH Host:${NC}          ${CYAN}${SETUP_DOMAIN}${NC}"
else
    echo -e "  ${BOLD}🌐 Admin Dashboard:${NC}        ${CYAN}http://${PUBLIC_IP}:${PANEL_PORT}/admin${NC}"
    echo -e "  ${BOLD}🔗 Subscription URL:${NC}       ${CYAN}http://${PUBLIC_IP}:${PANEL_PORT}/sub${NC}"
fi
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"
