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

# ==========================================================
# FIXED VERSIONS
# ==========================================================

FRAPPE_COMMIT="4fa1b14"
ERPNext_COMMIT="26f0687"
HRMS_COMMIT="2238ff6"
BUILDER_COMMIT="34ee4ee"

# ==========================================================
# START
# ==========================================================

echo ""
echo "=========================================================="
echo " Frappe / ERPNext Docker"
echo " FIXED VERSION 15 ENVIRONMENT"
echo "=========================================================="
echo "Site:              ${FRAPPE_SITE_NAME}"
echo "Port:              ${FRAPPE_INTERNAL_PORT}"
echo "Bench:             ${BENCH_DIR}"
echo ""
echo "Frappe commit:     ${FRAPPE_COMMIT}"
echo "ERPNext commit:    ${ERPNext_COMMIT}"
echo "HRMS commit:       ${HRMS_COMMIT}"
echo "Builder commit:    ${BUILDER_COMMIT}"
echo "=========================================================="
echo ""

mkdir -p /home/frappe

chown -R frappe:frappe /home/frappe

cd /home/frappe

# ==========================================================
# 1. CREATE BENCH
# ==========================================================

if [ ! -d "${BENCH_DIR}/apps/frappe" ]; then

    echo ">>> Creating Frappe Bench..."

    bench init \
        --skip-redis-config-generation \
        --frappe-branch version-15 \
        "${BENCH_DIR}"

else

    echo ">>> Existing Bench detected."

fi

cd "${BENCH_DIR}"

# ==========================================================
# 2. FORCE FRAPPE COMMIT
# ==========================================================

echo ""
echo ">>> Locking Frappe to commit ${FRAPPE_COMMIT}..."

cd apps/frappe

git fetch --depth 1 origin "${FRAPPE_COMMIT}" || true

git checkout --force "${FRAPPE_COMMIT}"

cd "${BENCH_DIR}"

# ==========================================================
# 3. VERIFY FRAPPE
# ==========================================================

echo ""
echo ">>> Verifying Frappe..."

FRAPPE_VERSION=$(./env/bin/python -c "
import sys
sys.path.insert(0, 'apps')
import frappe
print(frappe.__version__)
")

FRAPPE_GIT_COMMIT=$(git -C apps/frappe rev-parse HEAD)

echo "Frappe version: ${FRAPPE_VERSION}"
echo "Frappe commit:  ${FRAPPE_GIT_COMMIT}"

case "${FRAPPE_VERSION}" in
    15.*)
        echo "OK: Frappe Version 15"
        ;;
    *)
        echo ""
        echo "ERROR: Frappe is NOT Version 15."
        echo "Detected: ${FRAPPE_VERSION}"
        exit 1
        ;;
esac

# ==========================================================
# 4. MARIADB
# ==========================================================

echo ""
echo ">>> Configuring MariaDB..."

bench set-config -g db_host mariadb
bench set-config -g db_port 3306

# ==========================================================
# 5. REDIS
# ==========================================================

echo ""
echo ">>> Configuring Redis..."

bench set-config -g redis_cache "redis://redis:6379"
bench set-config -g redis_queue "redis://redis:6379"
bench set-config -g redis_socketio "redis://redis:6379"

# ==========================================================
# 6. ERPNext
# ==========================================================

if [ ! -d "${BENCH_DIR}/apps/erpnext" ]; then

    echo ""
    echo ">>> Downloading ERPNext..."

    bench get-app \
        --branch version-15 \
        erpnext \
        https://github.com/frappe/erpnext.git

else

    echo ""
    echo ">>> ERPNext already exists."

fi

echo ">>> Locking ERPNext to ${ERPNext_COMMIT}..."

git -C apps/erpnext fetch --depth 1 origin "${ERPNext_COMMIT}" || true
git -C apps/erpnext checkout --force "${ERPNext_COMMIT}"

# ==========================================================
# 7. HRMS
# ==========================================================

if [ ! -d "${BENCH_DIR}/apps/hrms" ]; then

    echo ""
    echo ">>> Downloading HRMS..."

    bench get-app \
        --branch version-15 \
        hrms \
        https://github.com/frappe/hrms.git

else

    echo ""
    echo ">>> HRMS already exists."

fi

echo ">>> Locking HRMS to ${HRMS_COMMIT}..."

git -C apps/hrms fetch --depth 1 origin "${HRMS_COMMIT}" || true
git -C apps/hrms checkout --force "${HRMS_COMMIT}"

# ==========================================================
# 8. BUILDER
# ==========================================================

if [ ! -d "${BENCH_DIR}/apps/builder" ]; then

    echo ""
    echo ">>> Downloading Builder..."

    bench get-app \
        --branch master \
        builder \
        https://github.com/frappe/builder.git

else

    echo ""
    echo ">>> Builder already exists."

fi

echo ">>> Locking Builder to ${BUILDER_COMMIT}..."

git -C apps/builder fetch --depth 1 origin "${BUILDER_COMMIT}" || true
git -C apps/builder checkout --force "${BUILDER_COMMIT}"

# ==========================================================
# 9. INSTALL DEPENDENCIES
# ==========================================================

echo ""
echo ">>> Installing Python dependencies..."

bench setup requirements

# ==========================================================
# 10. CREATE SITE
# ==========================================================

if [ ! -d "${BENCH_DIR}/sites/${FRAPPE_SITE_NAME}" ]; then

    echo ""
    echo ">>> Creating site: ${FRAPPE_SITE_NAME}"

    bench new-site "${FRAPPE_SITE_NAME}" \
        --db-host mariadb \
        --db-port 3306 \
        --db-root-password "${MYSQL_ROOT_PASSWORD}" \
        --admin-password "${FRAPPE_ADMIN_PASSWORD}" \
        --mariadb-user-host-login-scope='%'

else

    echo ""
    echo ">>> Site already exists."

fi

# ==========================================================
# 11. INSTALL ERPNext
# ==========================================================

if ! bench --site "${FRAPPE_SITE_NAME}" list-apps | grep -q "^erpnext"; then

    echo ""
    echo ">>> Installing ERPNext..."

    bench --site "${FRAPPE_SITE_NAME}" install-app erpnext

fi

# ==========================================================
# 12. INSTALL HRMS
# ==========================================================

if ! bench --site "${FRAPPE_SITE_NAME}" list-apps | grep -q "^hrms"; then

    echo ""
    echo ">>> Installing HRMS..."

    bench --site "${FRAPPE_SITE_NAME}" install-app hrms

fi

# ==========================================================
# 13. INSTALL BUILDER
# ==========================================================

if ! bench --site "${FRAPPE_SITE_NAME}" list-apps | grep -q "^builder"; then

    echo ""
    echo ">>> Installing Builder..."

    bench --site "${FRAPPE_SITE_NAME}" install-app builder

fi

# ==========================================================
# 14. DEVELOPER MODE
# ==========================================================

echo ""
echo ">>> Enabling developer mode..."

bench --site "${FRAPPE_SITE_NAME}" set-config developer_mode 1

# ==========================================================
# 15. SERVER SCRIPTS
# ==========================================================

bench --site "${FRAPPE_SITE_NAME}" set-config server_script_enabled 1

# ==========================================================
# 16. CLEAR CACHE
# ==========================================================

echo ""
echo ">>> Clearing cache..."

bench --site "${FRAPPE_SITE_NAME}" clear-cache
bench --site "${FRAPPE_SITE_NAME}" clear-website-cache

# ==========================================================
# 17. DEFAULT SITE
# ==========================================================

bench use "${FRAPPE_SITE_NAME}"

# ==========================================================
# 18. BUILD ASSETS
# ==========================================================

echo ""
echo ">>> Building assets..."

bench build

# ==========================================================
# 19. SUPERVISOR
# ==========================================================

echo ""
echo ">>> Generating Supervisor configuration..."

bench setup supervisor --skip-redis

SUPERVISOR_CONF="${BENCH_DIR}/config/supervisor.conf"

if [ -f "${SUPERVISOR_CONF}" ]; then

    sed -i \
        "s/bench serve --port [0-9]*/bench serve --port ${FRAPPE_INTERNAL_PORT}/g" \
        "${SUPERVISOR_CONF}"

fi

# ==========================================================
# 20. FINAL VERIFICATION
# ==========================================================

echo ""
echo "=========================================================="
echo " FINAL VERSION VERIFICATION"
echo "=========================================================="

bench version

echo ""
echo "Installed applications:"
bench --site "${FRAPPE_SITE_NAME}" list-apps

echo ""
echo "Git commits:"
echo "Frappe:"
git -C apps/frappe rev-parse HEAD

echo "ERPNext:"
git -C apps/erpnext rev-parse HEAD

echo "HRMS:"
git -C apps/hrms rev-parse HEAD

echo "Builder:"
git -C apps/builder rev-parse HEAD

echo ""
echo "=========================================================="
echo " STARTING SUPERVISOR"
echo "=========================================================="

exec supervisord \
    -n \
    -c "${SUPERVISOR_CONF}"
