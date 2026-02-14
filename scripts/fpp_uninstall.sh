#!/bin/bash

load_common() {
    local had_nounset=0
    case "$-" in
        *u*)
            had_nounset=1
            set +u
            ;;
    esac

    LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"

    local rc=1
    if [ -n "${FPPDIR:-}" ] && [ -f "${FPPDIR}/scripts/common" ]; then
        . "${FPPDIR}/scripts/common"
        rc=0
    elif [ -f "/opt/fpp/scripts/common" ]; then
        . "/opt/fpp/scripts/common"
        rc=0
    elif [ -f "/home/fpp/fpp/scripts/common" ]; then
        . "/home/fpp/fpp/scripts/common"
        rc=0
    else
        echo "Unable to locate FPP common script" >&2
        rc=1
    fi

    if [ "${had_nounset}" -eq 1 ]; then
        set -u
    fi

    return "${rc}"
}

load_common || exit 1

PLUGIN_NAME="fpp-AirPlayMatrix"
PLUGIN_DIR="${PLUGINDIR}/${PLUGIN_NAME}"
if [ ! -d "${PLUGIN_DIR}" ]; then
    PLUGIN_DIR=$(cd "$(dirname "$0")/.." && pwd)
fi

"${PLUGIN_DIR}/scripts/airplay_matrix_manager.sh" stop >/dev/null 2>&1 || true
rm -rf "${MEDIADIR}/tmp/${PLUGIN_NAME}" >/dev/null 2>&1 || true

if command -v sudo >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
        rm -f /etc/sudoers.d/fpp-airplaymatrix >/dev/null 2>&1 || true
    else
        sudo rm -f /etc/sudoers.d/fpp-airplaymatrix >/dev/null 2>&1 || true
    fi
fi

echo "${PLUGIN_NAME} uninstall complete"
