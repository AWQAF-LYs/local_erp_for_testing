#!/bin/bash

set -e

export PATH="/home/frappe/.local/bin:$PATH"

ENV_FILE="/home/frappe/env.config"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

FRAPPE_SITE_NAME="${FRAPPE_SITE_NAME:-erpnext.local}"
FRAPPE_INTERNAL_PORT="${FRAPPE_INTERNAL_PORT:-8000}"

BENCH_DIR="/home/frappe/frappe-bench"

echo "=========================================="
echo " Frappe / ERPNext Version 15"
echo "=========================================="
echo "Site: ${FRAPPE_SITE_NAME}"
echo "Port: ${FRAPPE_INTERNAL_PORT}"
echo "Bench: ${BENCH_DIR}"
echo "=========================================="

mkdir -p /home/frappe

chown -R frappe:frappe /home/frappe

cd /home/frappe

# --------------------------------------------------
# 1. Create Frappe Bench - VERSION 15
# --------------------------------------------------

if [ ! -d "${BENCH_DIR}/apps/frappe" ]; then

    echo "Creating Frappe Bench using VERSION 15..."

    bench init \
        --skip-redis-config-generation \
        --frappe-branch version-15 \
        "${BENCH_DIR}"

else

    echo "Existing Frappe Bench detected."

fi

cd "${BENCH_DIR}"

# --------------------------------------------------
# 2. Verify Frappe version / branch
# --------------------------------------------------

echo ""
echo "Checking Frappe installation..."

if [ ! -d "apps/frappe" ]; then
    echo "ERROR: Frappe was not installed."
    exit 1
fi

FRAPPE_VERSION=$(python -c "
import sys
sys.path.insert(0, 'apps')
import frappe
print(frappe.__version__)
")

echo "Installed Frappe version: ${FRAPPE_VERSION}"

case "${FRAPPE_VERSION}" in
    15.*)
        echo "OK: Frappe Version 15 detected."
        ;;
    *)
        echo "ERROR: Frappe is NOT Version 15."
        echo "Detected version: ${FRAPPE_VERSION}"
        exit 1
        ;;
esac

# --------------------------------------------------
# 3. MariaDB configuration
# --------------------------------------------------

echo ""
echo "Configuring MariaDB..."

bench set-config -g db_host mariadb
bench set-config -g db_port 3306

# --------------------------------------------------
# 4. Redis configuration
# --------------------------------------------------

echo ""
echo "Configuring Redis..."

bench set-config -g redis_cache "redis://redis:6379"
bench set-config -g redis_queue "redis://redis:6379"
bench set-config -g redis_socketio "redis://redis:6379"

# --------------------------------------------------
# 5. Get ERPNext VERSION 15
# --------------------------------------------------

if [ ! -d "apps/erpnext" ]; then

    echo ""
    echo "Downloading ERPNext VERSION 15..."

    bench get-app \
        --branch version-15 \
        erpnext \
        https://github.com/frappe/erpnext.git

else

    echo "ERPNext already exists."

fi

# --------------------------------------------------
# 6. Get HRMS VERSION 15
# --------------------------------------------------

if [ ! -d "apps/hrms" ]; then

    echo ""
    echo "Downloading HRMS VERSION 15..."

    bench get-app \
        --branch version-15 \
        hrms \
        https://github.com/frappe/hrms.git

else

    echo "HRMS already exists."

fi

# --------------------------------------------------
# 7. Get Builder VERSION 15
# --------------------------------------------------

if [ ! -d "apps/builder" ]; then

    echo ""
    echo "Downloading Builder VERSION 15..."

    bench get-app \
        --branch version-15 \
        builder \
        https://github.com/frappe/builder.git

else

    echo "Builder already exists."

fi

# --------------------------------------------------
# 8. Create Site
# --------------------------------------------------

if [ ! -d "sites/${FRAPPE_SITE_NAME}" ]; then

    echo ""
    echo "Creating site: ${FRAPPE_SITE_NAME}"

    bench new-site "${FRAPPE_SITE_NAME}" \
        --db-host mariadb \
        --db-port 3306 \
        --db-root-password "${MYSQL_ROOT_PASSWORD}" \
        --admin-password "${FRAPPE_ADMIN_PASSWORD}" \
        --mariadb-user-host-login-scope='%'

else

    echo "Site already exists: ${FRAPPE_SITE_NAME}"

fi

# --------------------------------------------------
# 9. Install ERPNext
# --------------------------------------------------

if ! bench --site "${FRAPPE_SITE_NAME}" list-apps | grep -q "^erpnext"; then

    echo ""
    echo "Installing ERPNext..."

    bench --site "${FRAPPE_SITE_NAME}" install-app erpnext

fi

# --------------------------------------------------
# 10. Install HRMS
# --------------------------------------------------

if ! bench --site "${FRAPPE_SITE_NAME}" list-apps | grep -q "^hrms"; then

    echo ""
    echo "Installing HRMS..."

    bench --site "${FRAPPE_SITE_NAME}" install-app hrms

fi

# --------------------------------------------------
# 11. Install Builder
# --------------------------------------------------

if ! bench --site "${FRAPPE_SITE_NAME}" list-apps | grep -q "^builder"; then

    echo ""
    echo "Installing Builder..."

    bench --site "${FRAPPE_SITE_NAME}" install-app builder

fi

# --------------------------------------------------
# 12. Developer mode
# --------------------------------------------------

echo ""
echo "Enabling developer mode..."

bench --site "${FRAPPE_SITE_NAME}" set-config developer_mode 1

# --------------------------------------------------
# 13. Clear cache
# --------------------------------------------------

echo ""
echo "Clearing cache..."

bench --site "${FRAPPE_SITE_NAME}" clear-cache
bench --site "${FRAPPE_SITE_NAME}" clear-website-cache

# --------------------------------------------------
# 14. Set default site
# --------------------------------------------------

bench use "${FRAPPE_SITE_NAME}"

# --------------------------------------------------
# 15. Generate supervisor configuration
# --------------------------------------------------

echo ""
echo "Generating Supervisor configuration..."

bench setup supervisor --skip-redis

# --------------------------------------------------
# 16. Change web port
# --------------------------------------------------

SUPERVISOR_CONF="/home/frappe/frappe-bench/config/supervisor.conf"

if [ -f "${SUPERVISOR_CONF}" ]; then

    sed -i \
        "s/bench serve --port [0-9]*/bench serve --port ${FRAPPE_INTERNAL_PORT}/g" \
        "${SUPERVISOR_CONF}"

fi

# --------------------------------------------------
# 17. Final verification
# --------------------------------------------------

echo ""
echo "=========================================="
echo " FINAL VERSION CHECK"
echo "=========================================="

bench version

echo ""
echo "Installed applications:"
bench --site "${FRAPPE_SITE_NAME}" list-apps

echo ""
echo "=========================================="
echo " Starting Supervisor"
echo "=========================================="

exec supervisord \
    -n \
    -c "${SUPERVISOR_CONF}"
