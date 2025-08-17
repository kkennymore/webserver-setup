# All-in-One VPS Setup Script with Cockpit, Mailserver, Roundcube, and Monitoring Stack

**Author:** Kenneth / Flaretech
**Last Updated:** 2025-08-17

---

## Overview

This script is a **production-ready VPS deployment solution** that sets up:

* **Cockpit**: Web-based server manager
* **Docker Mailserver + Roundcube + PostfixAdmin**: Email sending, receiving, and management
* **Database (MySQL/MariaDB) + PhpMyAdmin**: Database server with web UI
* **Messaging Brokers**: RabbitMQ & MQTT (Mosquitto/EMQX)
* **Monitoring & Visualization**: Prometheus + Grafana
* **Container Management**: Portainer
* **Reverse Proxy & TLS**: Nginx + Let's Encrypt companion
* **Persistent volumes, logs, and healthchecks**

The script is designed for **Linux servers (Ubuntu, Debian, Fedora, CentOS)** and automates:

* Docker installation
* User creation and permissions
* Mailserver configuration (DKIM, SPF, TLS, SpamAssassin, ClamAV)
* Docker Compose generation
* Container orchestration and deployment

---

## Features

* **Persistent volumes** for databases, logs, and mail data
* **Automatic network creation** for container communication
* **Healthchecks** and monitoring-ready deployment
* **Secure default configuration** with TLS via Let's Encrypt
* **Supports production domains and multiple services** with custom environment variables
* **Full cleanup mechanism** to reset Docker containers, volumes, and networks

---

## Prerequisites

* A VPS with a Linux OS (Ubuntu, Debian, Fedora, CentOS)
* Root or sudo access
* Docker and Docker Compose (script can install if missing)
* Public DNS pointing for your domains (mail, cockpit, phpmyadmin, etc.)

---

## Configuration Variables

Located at the top of the script:

```bash
DEPLOY_DIR=/opt/cockpit
PROXY_NET=monitoring
COCKPIT_DOMAIN="server.kxprex.com"
POSTFIXADMIN_DOMAIN="mailmanager.kxprex.com"
PHPMYADMIN_DOMAIN="phpmyadmin.kxprex.com"
ROUNDCUBE_DOMAIN="mailserver.kxprex.com"
RABBITMQ_DOMAIN="rabbitmq.kxprex.com"
EMQX_DOMAIN="mqtt.kxprex.com"
PROMETHEUS_DOMAIN="prom.kxprex.com"
GRAFANA_DOMAIN="grafana.kxprex.com"
MAILSERVER_DOMAIN="mail.kxprex.com"
MAIN_DOMAIN="kxprex.com"
LETSENCRYPT_EMAIL=kenneth@kxprex.com
POSTMASTER_ADDRESS=postmaster@kxprex.com
DEFAULT_CONTACT_EMAIL="kenneth@kxprex.com"
NEW_USER="flareadmin"
```

**What these do:**

* `DEPLOY_DIR`: Root folder for all container volumes and configs
* `PROXY_NET`: Docker network used for Nginx reverse proxy
* `*_DOMAIN`: Hostnames used for each service
* `LETSENCRYPT_EMAIL`: Email used for automatic TLS certificate requests
* `POSTMASTER_ADDRESS`: Default mail postmaster address
* `NEW_USER`: Non-root user created with sudo + docker permissions

**Database and Ports** are also defined to maintain container persistence and avoid conflicts.

---

## Script Sections Explained

### 1. Bash Safety

```bash
set -euo pipefail
```

* `-e`: Exit on any command failure
* `-u`: Treat unset variables as errors
* `-o pipefail`: Fail if any command in a pipeline fails

Ensures safe, predictable execution.

---

### 2. Logging & Helper Functions

```bash
log() { printf '%s\n' "$*"; }
fatal() { printf 'ERROR: %s\n' "$*"; exit 1; }
```

* `log`: Prints messages to console
* `fatal`: Prints error and exits script

```bash
run_compose() { ... }
```

* Used to start services via Docker Compose
* Checks if compose file exists
* Forces recreation of containers

---

### 3. Docker Cleanup

```bash
cleanup_docker() { ... }
```

* Stops all running containers
* Removes containers, volumes, and user-defined networks
* Helps to **reset VPS before redeployment**

---

### 4. Root / OS Detection

```bash
ensure_root() { ... }
detect_os() { ... }
```

* Checks if script is running as root
* Detects Linux distribution
* Sets package manager commands (`apt-get` / `dnf`)
* Detects whether `ufw` firewall is available

---

### 5. System Packages & Docker

```bash
system_update_install() { ... }
install_docker() { ... }
```

* Updates system packages
* Installs dependencies: `curl`, `wget`, `git`, `jq`, `openssl`
* Installs Docker if not already installed
* Enables Docker service

---

### 6. User Creation

```bash
create_user() { ... }
```

* Creates non-root user (`flareadmin`)
* Adds user to `sudo` and `docker` groups
* For safer container management

---

### 7. Mailserver Environment

```bash
create_mailserver_env() { ... }
```

* Generates `.env` for `docker-mailserver`
* Configures:

  * Hostname, domain
  * TLS/SSL with Let's Encrypt
  * DKIM keys, SPF, and mail accounts
  * SpamAssassin, ClamAV, Fail2Ban

---

### 8. Docker Network

```bash
create_proxy_network() { ... }
```

* Ensures a Docker network exists for Nginx proxy
* Allows containers to communicate for reverse proxy routing

---

### 9. MySQL / Database Privileges

```bash
grant_full_mysql_privileges() { ... }
```

* Grants full privileges to user for:

  * PostfixAdmin database
  * Roundcube database
* Creates databases if they don’t exist

---

### 10. Docker Compose Generator

```bash
generate_compose() { ... }
```

* Creates necessary folders for Nginx, MySQL, Mailserver logs
* Generates `docker-compose.yml` dynamically
* Includes all services:

  * **Nginx Proxy + Let’s Encrypt**
  * **Cockpit**
  * **Docker Mailserver**
  * **Roundcube & PostfixAdmin**
  * **MySQL + PhpMyAdmin**
  * **RabbitMQ, Mosquitto, EMQX**
  * **Prometheus + Grafana**
  * **Portainer**
* Configures persistent volumes, ports, and networks
* Sets up environment variables for each service

---

### 11. Main Function

```bash
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
```

* Executes the full VPS setup in order:

  1. Cleanup old Docker containers
  2. Check OS and root privileges
  3. Install system packages + Docker
  4. Create admin user
  5. Setup Mailserver `.env`
  6. Create Docker networks
  7. Generate `docker-compose.yml`
  8. Deploy all containers
  9. Grant database privileges

---

## Usage

1. Make script executable:

```bash
chmod +x vps-setup.sh
```

2. Run as root:

```bash
sudo ./vps-setup.sh
```

3. After deployment, access services via domains:

| Service      | URL                                                              |
| ------------ | ---------------------------------------------------------------- |
| Cockpit      | [https://server.kxprex.com](https://server.kxprex.com)           |
| Roundcube    | [https://mailserver.kxprex.com](https://mailserver.kxprex.com)   |
| PostfixAdmin | [https://mailmanager.kxprex.com](https://mailmanager.kxprex.com) |
| PhpMyAdmin   | [https://phpmyadmin.kxprex.com](https://phpmyadmin.kxprex.com)   |
| Portainer    | [https://containers.kxprex.com](https://containers.kxprex.com)   |
| Prometheus   | [https://prom.kxprex.com](https://prom.kxprex.com)               |
| Grafana      | [https://grafana.kxprex.com](https://grafana.kxprex.com)         |
| RabbitMQ     | [https://rabbitmq.kxprex.com](https://rabbitmq.kxprex.com)       |
| EMQX         | [https://mqtt.kxprex.com](https://mqtt.kxprex.com)               |

> Ensure DNS records are configured for each subdomain.

---

## Notes & Recommendations

* **DNS & MX Records**: Required for Mailserver to send/receive emails
* **Cloudflare Users**: SMTP ports 25, 465, 587 must be open; Cloudflare only proxies HTTP/HTTPS
* **DKIM & SPF**: Configure in DNS for spam-proof mail
* **TLS Certificates**: Automatically generated via Let’s Encrypt companion

---

## License

MIT License

---
