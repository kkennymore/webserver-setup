#!/bin/bash
set -euo pipefail

# ====================================================
# All-in-one VPS setup script with Cockpit as manager
# Production-ready: persistent volumes, healthchecks, logs
# Uses docker-mailserver + Roundcube
# Includes Nginx Proxy + Let's Encrypt companion
# ====================================================

# -------------------------
# Configurable variables
# -------------------------
DEPLOY_DIR=/opt/cockpit
PROXY_NET=monitoring

# Hostnames / domains
COCKPIT_DOMAIN=""
POSTFIXADMIN_DOMAIN=""
PHPMYADMIN_DOMAIN=""
PORTAINER_DOMAIN=""
ROUNDCUBE_DOMAIN=""
RABBITMQ_DOMAIN=""
EMQX_DOMAIN=""
PROMETHEUS_DOMAIN=""
GRAFANA_DOMAIN=""
MAILSERVER_DOMAIN=""
MAIN_DOMAIN=""
LETSENCRYPT_EMAIL=
POSTMASTER_ADDRESS=

# Admins / emails
DEFAULT_CONTACT_EMAIL=""
NEW_USER=""

# Timezone
TZ_DEFAULT="UTC"

# Database credentials
DB_NAME=""
DB_USER=""
DB_PASSWORD=""

# Container names
COCKPIT_CONTAINER_NAME="cockpit"
ROUNDCUBE_CONTAINER_NAME="roundcube"
MAILSERVER_CONTAINER_NAME="mailserver"
MYSQL_CONTAINER_NAME="mysql"
PHPMYADMIN_CONTAINER_NAME="phpmyadmin"
RABBITMQ_CONTAINER_NAME="rabbitmq"
MOSQUITTO_CONTAINER_NAME="mosquitto"
EMQX_CONTAINER_NAME="emqx"
PROMETHEUS_CONTAINER_NAME="prometheus"
GRAFANA_CONTAINER_NAME="grafana"
NGINX_PROXY_CONTAINER="nginx-proxy"
LETSENCRYPT_CONTAINER="nginx-proxy-letsencrypt"
PORTAINER_CONTAINER_NAME="portainer"
POSTFIX_ADMIN_CONTAINER_NAME="postfixadmin"

# Ports
MOSQUITTO_PORT=1883
MOSQUITTO_WS_PORT=9001
EMQX_LISTENER_TCP_EXTERNAL=1884
EMQX_LISTENER_SSL_EXTERNAL=8884
EMQX_LISTENER_WS_EXTERNAL=8085
EMQX_LISTENER_WSS_EXTERNAL=8086
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
PHPMYADMIN_PORT=8082
DB_PORT=3306
PORTAINER_PORT=9000
ROUNDCUBE_PORT=8999
COCKPIT_PORT=9999
POST_FIX_ADMIN_PORT=9987

LOCALHOST="127.0.0.1"
MACHINE_IP=""

POSTFIX_DBNAME=postfix
ROUNDCUBE_DB_NAME=roundcube
# RabbitMQ
RABBITMQ_USER=""
RABBITMQ_PASSWORD=""

# EMQX Dashboard
EMQX_DASHBOARD_USER=""
EMQX_DASHBOARD_PASSWORD=""

# -------------------------
# Helpers
# -------------------------
log() { printf '%s\n' "$*"; }
fatal() { printf 'ERROR: %s\n' "$*"; exit 1; }
run_compose() {
  local file="$1"; local label="$2"
  if [ ! -f "$file" ]; then
    log "Compose file $file not found, skipping $label"
    return 1
  fi
  log "Bringing up $label using docker compose file $file"
  docker compose -f "$file" up -d --force-recreate
}

# -------------------------
# Cleanup Docker containers and volumes
# -------------------------
cleanup_docker() {
    echo "Stopping all Docker containers..."
    docker ps -q | xargs -r docker stop

    echo "Removing all Docker containers..."
    docker ps -a -q | xargs -r docker rm -f

    echo "Removing all Docker volumes..."
    docker volume ls -q | xargs -r docker volume rm -f

    echo "Removing all Docker networks (optional, only user-defined networks)..."
    docker network ls --filter "type=custom" -q | xargs -r docker network rm

    echo "Docker cleanup complete."
}

# -------------------------
# Root / OS detection
# -------------------------
ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fatal "Script must be run as root"
  fi
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      ubuntu|debian)
        PKG_INSTALL="apt-get install -y --no-install-recommends"
        UPDATE_CMD="apt-get update -y"
        UPGRADE_CMD="apt-get upgrade -y"
        USE_UFW=true
        ;;
      fedora|centos|rhel)
        PKG_INSTALL="dnf install -y"
        UPDATE_CMD="dnf check-update -y || true"
        UPGRADE_CMD="dnf upgrade -y"
        USE_UFW=false
        ;;
      *)
        PKG_INSTALL="apt-get install -y --no-install-recommends"
        UPDATE_CMD="apt-get update -y"
        UPGRADE_CMD="apt-get upgrade -y"
        USE_UFW=true
        ;;
    esac
  else
    fatal "Unable to detect OS."
  fi
  log "Detected OS: $ID"
}

# -------------------------
# System packages & docker
# -------------------------
system_update_install() {
  eval "$UPDATE_CMD"
  eval "$UPGRADE_CMD"
  eval "$PKG_INSTALL curl wget git lsb-release ca-certificates gnupg jq openssl"
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker"
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
  else
    log "Docker already installed"
    systemctl enable --now docker || true
  fi
}

create_user() {
  if ! id "$NEW_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$NEW_USER" || true
    usermod -aG sudo,docker "$NEW_USER" || true
    log "User $NEW_USER created and added to sudo,docker groups"
  fi
}


create_mailserver_env() {
  # Ensure DEPLOY_DIR exists
  mkdir -p "${DEPLOY_DIR}"

  # Create the .env file
  cat > "${DEPLOY_DIR}/${MAILSERVER_CONTAINER_NAME}.env" <<EOF
# -------------------------
# Mailserver environment
# -------------------------

# Host & domain
MAILSERVER_HOSTNAME=${MAILSERVER_CONTAINER_NAME}
MAILSERVER_DOMAIN=${MAILSERVER_DOMAIN}
POSTMASTER_ADDRESS=${POSTMASTER_ADDRESS}

# TLS / SSL
SSL_TYPE=letsencrypt
ENABLE_TLS=1
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
LETSENCRYPT_DOMAIN=${MAIN_DOMAIN}

# Mailserver features
ENABLE_SPAMASSASSIN=1
ENABLE_CLAMAV=1
ENABLE_FAIL2BAN=1
ENABLE_POSTGREY=0
ONE_DIR=1
DMS_DEBUG=0
ENABLE_MANAGESIEVE=1
LOG_LEVEL=info

# Accounts (format: user@domain|password)
ACCOUNTS=flareadmin@flaretechmusic.com|SuperSecurePass123

# DKIM / OpenDKIM
ENABLE_DKIM=1
DKIM_SELECTOR=mail
DKIM_DOMAIN=${MAIN_DOMAIN}
# Recommended: store DKIM keys in /tmp/docker-mailserver/opendkim/keys for persistence

# Postfix relay (optional if you use an external relay)
# RELAY_HOST=
# RELAY_PORT=
# RELAY_USER=
# RELAY_PASSWORD=

# Network / Cloudflare considerations
# If you are behind Cloudflare proxy, make sure to allow ports 25, 587, 465 externally.
# Cloudflare only proxies HTTP/HTTPS, not SMTP.
# Ensure proper MX record: mail.flaretechmusic.com → IP of your VPS
EOF

  echo "✅ Mailserver environment file created at: ${DEPLOY_DIR}/mailserver.env"
}

create_proxy_network() {
  if ! docker network ls --format '{{.Name}}' | grep -q "^${PROXY_NET}\$"; then
    docker network create "${PROXY_NET}"
    log "Created docker network ${PROXY_NET}"
  else
    log "Docker network ${PROXY_NET} already exists"
  fi
}

grant_full_mysql_privileges() {
  docker exec -i ${MYSQL_CONTAINER_NAME} mysql -uroot -p"${DB_PASSWORD}" <<EOF
GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

CREATE DATABASE IF NOT EXISTS \`${POSTFIX_DBNAME}\`;
CREATE DATABASE IF NOT EXISTS \`${POSTFIX_DBNAME}_analytics\`;

CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${POSTFIX_DBNAME}\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${POSTFIX_DBNAME}_analytics\`.* TO '${DB_USER}'@'%';

FLUSH PRIVILEGES;

# roundcube

CREATE DATABASE IF NOT EXISTS \`${ROUNDCUBE_DB_NAME}\`;

CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${ROUNDCUBE_DB_NAME}\`.* TO '${DB_USER}'@'%';

FLUSH PRIVILEGES;
EOF
  echo "✅ Granted full privileges to ${DB_USER}"
}


# -------------------------
# Generate Docker Compose
# -------------------------
generate_compose() {
  mkdir -p "${DEPLOY_DIR}/nginx/certs" \
           "${DEPLOY_DIR}/nginx/vhost.d" \
           "${DEPLOY_DIR}/nginx/html" \
           "${DEPLOY_DIR}/mysql_data" \
           "${DEPLOY_DIR}/mailserver_data" \
           "${DEPLOY_DIR}/logs"

  COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"

  cat > "$COMPOSE_FILE" <<EOF
networks:
  mailnet:
    driver: bridge
  ${PROXY_NET}:
    external: true

services:

  # ---------- Nginx Proxy ----------
  ${NGINX_PROXY_CONTAINER}:
    image: jwilder/nginx-proxy:latest
    container_name: ${NGINX_PROXY_CONTAINER}
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ${DEPLOY_DIR}/nginx/certs:/etc/nginx/certs:rw
      - ${DEPLOY_DIR}/nginx/vhost.d:/etc/nginx/vhost.d:rw
      - ${DEPLOY_DIR}/nginx/html:/usr/share/nginx/html:rw
    networks:
      - ${PROXY_NET}

  # ---------- Let's Encrypt Companion ----------
  # ${LETSENCRYPT_CONTAINER}:
  #   image: jrcs/letsencrypt-nginx-proxy-companion:latest
  #   container_name: ${LETSENCRYPT_CONTAINER}
  #   restart: unless-stopped
  #   environment:
  #     NGINX_PROXY_CONTAINER: ${NGINX_PROXY_CONTAINER}
  #     ACME_CA_URI: https://acme-v02.api.letsencrypt.org/directory
  #   volumes:
  #     - /var/run/docker.sock:/var/run/docker.sock:ro
  #     - ${DEPLOY_DIR}/nginx/certs:/etc/nginx/certs:rw
  #     - ${DEPLOY_DIR}/nginx/vhost.d:/etc/nginx/vhost.d:rw
  #     - ${DEPLOY_DIR}/nginx/html:/usr/share/nginx/html:rw
  #   depends_on:
  #     - ${NGINX_PROXY_CONTAINER}
  #   networks:
  #     - ${PROXY_NET}

  ${LETSENCRYPT_CONTAINER}:
    image: nginxproxy/acme-companion
    container_name: ${LETSENCRYPT_CONTAINER}
    restart: always
    networks: 
      - ${PROXY_NET}
    depends_on:
      - ${NGINX_PROXY_CONTAINER}
    environment:
      - DEFAULT_EMAIL=${LETSENCRYPT_EMAIL}
      - NGINX_PROXY_CONTAINER=${NGINX_PROXY_CONTAINER}
    volumes:
      - ${DEPLOY_DIR}/nginx/certs:/etc/nginx/certs
      - ${DEPLOY_DIR}/nginx/vhost.d:/etc/nginx/vhost.d
      - ${DEPLOY_DIR}/nginx/html:/usr/share/nginx/html
      - /var/run/docker.sock:/var/run/docker.sock:ro

  # ---------- Cockpit ----------
  ${COCKPIT_CONTAINER_NAME}:
    image: quay.io/cockpit/ws:latest
    container_name: ${COCKPIT_CONTAINER_NAME}
    restart: unless-stopped
    # privileged: true
    environment:
      VIRTUAL_HOST: "${COCKPIT_DOMAIN}"
      LETSENCRYPT_HOST: "${COCKPIT_DOMAIN}"
      LETSENCRYPT_EMAIL: "${DEFAULT_CONTACT_EMAIL}"
      # COCKPIT_BIND_LOCAL: "0"
      # COCKPIT_KIOSK_MODE: "1"
      # COCKPIT_REMOTE_HOST: ${MACHINE_IP}
      # COCKPIT_DISABLE_PAM_LABELS: "1"
    ports:
      - "${LOCALHOST}:${COCKPIT_PORT}:9090"
    networks:
      - ${PROXY_NET}

  # ---------- Docker Mailserver ----------
  ${MAILSERVER_CONTAINER_NAME}:
    image: mailserver/docker-mailserver:edge
    container_name: ${MAILSERVER_CONTAINER_NAME}
    hostname: mail
    domainname: ${MAILSERVER_DOMAIN}
    restart: unless-stopped
    env_file:
      - ${DEPLOY_DIR}/mailserver.env
    ports:
      - "25:25"       # SMTP (inbound mail)
      - "465:465"     # SMTPS
      - "587:587"     # Submission
      - "143:143"     # IMAP
      - "993:993"     # IMAPS
    volumes:
      - ${DEPLOY_DIR}/mailserver_data:/var/mail
      - ${DEPLOY_DIR}/logs:/var/log/mail
      - ${DEPLOY_DIR}/mailserver/config/:/tmp/docker-mailserver/
    networks:
      - mailnet
      - ${PROXY_NET}
    environment:
      ENABLE_SPAMASSASSIN: "1"
      ENABLE_CLAMAV: "1"
      ENABLE_FAIL2BAN: "1"
      ENABLE_POSTGREY: "0"
      ONE_DIR: "1"
      DMS_DEBUG: "0"

  # ---------- Roundcube ----------
  ${ROUNDCUBE_CONTAINER_NAME}:
    image: roundcube/roundcubemail:latest
    container_name: ${ROUNDCUBE_CONTAINER_NAME}
    restart: always
    environment:
      VIRTUAL_HOST: ${ROUNDCUBE_DOMAIN}
      LETSENCRYPT_HOST: ${ROUNDCUBE_DOMAIN}
      LETSENCRYPT_EMAIL: ${DEFAULT_CONTACT_EMAIL}
      ROUNDCUBE_DEFAULT_HOST: "ssl://${MAILSERVER_DOMAIN}"
      ROUNDCUBE_SMTP_SERVER: "tls://${MAILSERVER_DOMAIN}"
      ROUNDCUBE_SMTP_PORT: 587
      ROUNDCUBE_DB_TYPE: mysql
      ROUNDCUBE_DB_HOST: ${MYSQL_CONTAINER_NAME}
      ROUNDCUBE_DB_USER: ${DB_USER}
      ROUNDCUBE_DB_PASSWORD: ${DB_PASSWORD}
      ROUNDCUBE_DB_NAME: ${ROUNDCUBE_DB_NAME}
    depends_on:
      - ${MYSQL_CONTAINER_NAME}
      - ${MAILSERVER_CONTAINER_NAME}
    ports:
      - "${ROUNDCUBE_PORT}:80"
    networks:
      - mailnet
      - ${PROXY_NET}

  # ---------- MySQL ----------
  ${MYSQL_CONTAINER_NAME}:
    image: mysql:8
    container_name: ${MYSQL_CONTAINER_NAME}
    restart: always
    security_opt:
      - seccomp=unconfined
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "${MYSQL_CONTAINER_NAME}"]
      interval: 5s
      timeout: 3s
      retries: 10
    environment:
      VIRTUAL_HOST: ${LOCALHOST}
      LETSENCRYPT_HOST: ${LOCALHOST}
      LETSENCRYPT_EMAIL: ${DEFAULT_CONTACT_EMAIL}
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
      MYSQL_ALLOW_EMPTY_PASSWORD: "no"
      MYSQL_SSL_DISABLED: "true"
    ports:
      - "${DB_PORT}:3306"
    volumes:
      - ${DEPLOY_DIR}/mysql_data:/var/lib/mysql
    networks:
      - mailnet
      - ${PROXY_NET}

  # ---------- PhpMyAdmin ----------
  ${PHPMYADMIN_CONTAINER_NAME}:
    image: phpmyadmin/phpmyadmin
    container_name: ${PHPMYADMIN_CONTAINER_NAME}
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: ${PHPMYADMIN_DOMAIN}
      LETSENCRYPT_HOST: ${PHPMYADMIN_DOMAIN}
      LETSENCRYPT_EMAIL: ${DEFAULT_CONTACT_EMAIL}
      POSTFIXADMIN_DB_TYPE: mysqli
      PMA_HOST: ${MYSQL_CONTAINER_NAME}
      PMA_PORT: ${DB_PORT}
      PMA_ALLOW_NO_PASSWORD: "false"
    ports:
      - "${LOCALHOST}:${PHPMYADMIN_PORT}:80"
    depends_on:
      - ${MYSQL_CONTAINER_NAME}
    command: >
      bash -c "echo 'ServerName localhost' >> /etc/apache2/apache2.conf && 
      echo '<?php' >> /etc/phpmyadmin/config.secret.inc.php &&
      echo '"\$"cfg[\"blowfish_secret\"] = \"gK!8t39Vx2\$zP@lwQ9mNe#7KsFg\$1ZrM\";' >> /etc/phpmyadmin/config.secret.inc.php &&
      echo '"\$"cfg[\"Servers\"][1][\"port\"] = \"${DB_PORT}\";' >> /etc/phpmyadmin/config.secret.inc.php &&
      echo '"\$"cfg[\"Servers\"][1][\"user\"] = \"${DB_USER}\";' >> /etc/phpmyadmin/config.secret.inc.php &&
      echo '"\$"cfg[\"Servers\"][1][\"password\"] = \"${DB_PASSWORD}\";' >> /etc/phpmyadmin/config.secret.inc.php &&
      echo '"\$"cfg[\"Servers\"][1][\"host\"] = \"${MYSQL_CONTAINER_NAME}\";' >> /etc/phpmyadmin/config.secret.inc.php && 
      echo '"\$"cfg[\"Servers\"][1][\"AllowRoot\"] = false;' >> /etc/phpmyadmin/config.secret.inc.php &&
      echo '"\$"cfg[\"Servers\"][1][\"AllowDeny\"][\"order\"] = \"deny,allow\";' >> /etc/phpmyadmin/config.secret.inc.php &&
      echo '"\$"cfg[\"Servers\"][1][\"AllowDeny\"][\"rules\"] = [\"deny root@%\",\"allow *@%\",];' >> /etc/phpmyadmin/config.secret.inc.php &&
      apache2-foreground"

    networks:
      - ${PROXY_NET}

  # ------postfix admin---------- 
  ${POSTFIX_ADMIN_CONTAINER_NAME}:
    image: postfixadmin:latest
    container_name: ${POSTFIX_ADMIN_CONTAINER_NAME}
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: ${POSTFIXADMIN_DOMAIN}
      LETSENCRYPT_HOST: ${POSTFIXADMIN_DOMAIN}
      LETSENCRYPT_EMAIL: ${DEFAULT_CONTACT_EMAIL}
      POSTFIXADMIN_DB_TYPE: mysqli
      POSTFIXADMIN_DB_HOST: ${MYSQL_CONTAINER_NAME}
      POSTFIXADMIN_DB_USER: ${DB_USER}
      POSTFIXADMIN_DB_NAME: ${POSTFIX_DBNAME}
      POSTFIXADMIN_DB_PASSWORD: ${DB_PASSWORD}
    depends_on:
      - "${MYSQL_CONTAINER_NAME}"
    ports:
      - "${LOCALHOST}:${POST_FIX_ADMIN_PORT}:80"
    networks:
      - ${PROXY_NET}

  # ---------- RabbitMQ ----------
  ${RABBITMQ_CONTAINER_NAME}:
    image: rabbitmq:3-management
    container_name: ${RABBITMQ_CONTAINER_NAME}
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: ${RABBITMQ_DOMAIN}
      LETSENCRYPT_HOST: ${RABBITMQ_DOMAIN}
      LETSENCRYPT_EMAIL: ${DEFAULT_CONTACT_EMAIL}
      RABBITMQ_DEFAULT_USER: "${RABBITMQ_USER}"
      RABBITMQ_DEFAULT_PASS: "${RABBITMQ_PASSWORD}"
    ports:
      - "${LOCALHOST}:5672:5672"
      - "${LOCALHOST}:15672:15672"
    networks:
      - ${PROXY_NET}

  # ---------- Mosquitto ----------
  ${MOSQUITTO_CONTAINER_NAME}:
    image: eclipse-mosquitto:latest
    container_name: ${MOSQUITTO_CONTAINER_NAME}
    restart: always
    ports:
      - "${MOSQUITTO_PORT}:1883"
      - "${MOSQUITTO_WS_PORT}:9001"
    networks:
      - ${PROXY_NET}

  # ---------- EMQX ----------
  ${EMQX_CONTAINER_NAME}:
    image: emqx/emqx:5.6.0
    container_name: ${EMQX_CONTAINER_NAME}
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: ${EMQX_DOMAIN}
      LETSENCRYPT_HOST: ${EMQX_DOMAIN}
      LETSENCRYPT_EMAIL: ${DEFAULT_CONTACT_EMAIL}
      EMQX_NAME: "${EMQX_CONTAINER_NAME}"
      EMQX_NODE__COOKIE: emqxsecretcookie
      EMQX_LISTENER__TCP__EXTERNAL: "${EMQX_LISTENER_TCP_EXTERNAL}"
      EMQX_LISTENER__SSL__EXTERNAL: "${EMQX_LISTENER_SSL_EXTERNAL}"
      EMQX_LISTENER__WS__EXTERNAL: "${EMQX_LISTENER_WS_EXTERNAL}"
      EMQX_LISTENER__WSS__EXTERNAL: "${EMQX_LISTENER_WSS_EXTERNAL}"
      EMQX_DASHBOARD__DEFAULT_USERNAME: "${EMQX_DASHBOARD_USER}"
      EMQX_DASHBOARD__DEFAULT_PASSWORD: "${EMQX_DASHBOARD_PASSWORD}"
    ports:
      - "${LOCALHOST}:18083:18083"
      - "${EMQX_LISTENER_TCP_EXTERNAL}:1883"
      - "${EMQX_LISTENER_SSL_EXTERNAL}:8883"
      - "${EMQX_LISTENER_WS_EXTERNAL}:8083"
      - "${EMQX_LISTENER_WSS_EXTERNAL}:8084"
    networks:
      - ${PROXY_NET}

  # ---------- Prometheus ----------
  ${PROMETHEUS_CONTAINER_NAME}:
    image: prom/prometheus:latest
    container_name: ${PROMETHEUS_CONTAINER_NAME}
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: ${PROMETHEUS_DOMAIN}
      LETSENCRYPT_HOST: ${PROMETHEUS_DOMAIN}
      LETSENCRYPT_EMAIL: ${DEFAULT_CONTACT_EMAIL}
    ports:
      - "${LOCALHOST}:${PROMETHEUS_PORT}:9090"
    networks:
      - ${PROXY_NET}

  # ---------- Grafana ----------
  ${GRAFANA_CONTAINER_NAME}:
    image: grafana/grafana:latest
    container_name: ${GRAFANA_CONTAINER_NAME}
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: ${GRAFANA_DOMAIN}
      LETSENCRYPT_HOST: ${GRAFANA_DOMAIN}
      LETSENCRYPT_EMAIL: ${DEFAULT_CONTACT_EMAIL}
    ports:
      - "${LOCALHOST}:${GRAFANA_PORT}:3000"
    networks:
      - ${PROXY_NET}

  ${PORTAINER_CONTAINER_NAME}:
    container_name: ${PORTAINER_CONTAINER_NAME}
    image: portainer/portainer-ce
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: ${PORTAINER_DOMAIN}
      LETSENCRYPT_HOST: ${PORTAINER_DOMAIN}
      LETSENCRYPT_EMAIL: ${DEFAULT_CONTACT_EMAIL}
    ports:
      - "${LOCALHOST}:${PORTAINER_PORT}:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${DEPLOY_DIR}/portainer:/data
    networks:
      - ${PROXY_NET}

volumes:
  mysql_data:
  mailserver_data:
EOF
}

# -------------------------
# Main
# -------------------------
main() {
  cleanup_docker
  ensure_root
  detect_os
  system_update_install
  install_docker
  create_user
  create_mailserver_env
  create_proxy_network
  generate_compose
  run_compose "${DEPLOY_DIR}/docker-compose.yml" "all services"
  sleep 5
  grant_full_mysql_privileges

  log "All containers deployed with healthchecks and persistent logs."
  log "Cockpit manages containers at https://${COCKPIT_DOMAIN}"
}

main "$@"
