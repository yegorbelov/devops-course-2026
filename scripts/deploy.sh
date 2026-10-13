#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

err() { echo "ERROR: $*" >&2; }

# 1. Разбор аргумента
DRY_RUN=0
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=1 ;;
    *)         err "неизвестный аргумент: $1"; echo "Использование: $0 [--dry-run]" >&2; exit 2 ;;
esac

# 2. Проверки (требования 4 и 5)
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    err "файл site/index.html отсутствует, доставка отменена"
    exit 1
fi
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    err "в репозитории есть незафиксированные изменения, доставка отменена"
    exit 1
fi

# 3. Синхронизация (одно SSH-соединение)
RSYNC_OPTS=(-avz --delete --chmod=D755,F644
            -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if (( DRY_RUN )); then
    RSYNC_OPTS+=(--dry-run)
fi
if ! rsync "${RSYNC_OPTS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"; then
    err "rsync завершился с ошибкой"
    exit 1
fi

# 4. При --dry-run выходим без проверки доступности
if (( DRY_RUN )); then
    echo "dry-run: сервер не изменён"
    exit 0
fi

# 5. Проверка доступности с проверкой сертификата (без -k)
if ! curl -fsS --max-time 10 --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
    err "ресурс ${SITE_URL} недоступен после доставки"
    exit 1
fi

echo "Доставлен коммит $(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
exit 0
