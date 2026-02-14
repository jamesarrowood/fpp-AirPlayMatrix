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

chmod +x "${PLUGIN_DIR}/scripts/airplay_matrix_manager.sh" 2>/dev/null || true
chmod +x "${PLUGIN_DIR}/scripts/airplay_matrixd.py" 2>/dev/null || true
chmod +x "${PLUGIN_DIR}/scripts/preStart.sh" 2>/dev/null || true
chmod +x "${PLUGIN_DIR}/scripts/preStop.sh" 2>/dev/null || true
chmod +x "${PLUGIN_DIR}/scripts/fpp_uninstall.sh" 2>/dev/null || true
chmod +x "${PLUGIN_DIR}/commands/start.sh" 2>/dev/null || true
chmod +x "${PLUGIN_DIR}/commands/stop.sh" 2>/dev/null || true
chmod +x "${PLUGIN_DIR}/commands/restart.sh" 2>/dev/null || true

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive

    APT_PREFIX=()
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            APT_PREFIX=(sudo)
        else
            echo "WARNING: apt-get requires root privileges and sudo was not found. Skipping dependency install." >&2
        fi
    fi

    if [ "${#APT_PREFIX[@]}" -gt 0 ] || [ "$(id -u)" -eq 0 ]; then
        echo "Installing package dependencies..."
        if ! "${APT_PREFIX[@]}" apt-get update -y; then
            echo "WARNING: apt-get update failed. Dependency installation may fail." >&2
        fi
        if ! "${APT_PREFIX[@]}" apt-get install -y \
            uxplay \
            gstreamer1.0-tools \
            gstreamer1.0-plugins-base \
            gstreamer1.0-plugins-good \
            gstreamer1.0-plugins-bad \
            gstreamer1.0-libav; then
            echo "WARNING: Failed to install one or more dependencies (uxplay/gstreamer)." >&2
            echo "         Install them manually, then restart the plugin." >&2
        fi
    fi
fi

# Grant passwordless sudo for manager so plugin API/UI can launch daemon as root.
if command -v sudo >/dev/null 2>&1; then
    SUDOERS_LINE="fpp ALL=(root) NOPASSWD: ${PLUGIN_DIR}/scripts/airplay_matrix_manager.sh *"
    if [ "$(id -u)" -eq 0 ]; then
        echo "${SUDOERS_LINE}" > /etc/sudoers.d/fpp-airplaymatrix
        chmod 440 /etc/sudoers.d/fpp-airplaymatrix
        visudo -cf /etc/sudoers.d/fpp-airplaymatrix >/dev/null 2>&1 || true
    else
        sudo bash -c "echo '${SUDOERS_LINE}' > /etc/sudoers.d/fpp-airplaymatrix" >/dev/null 2>&1 || true
        sudo chmod 440 /etc/sudoers.d/fpp-airplaymatrix >/dev/null 2>&1 || true
        sudo visudo -cf /etc/sudoers.d/fpp-airplaymatrix >/dev/null 2>&1 || true
    fi
fi

mkdir -p "${MEDIADIR}/tmp/${PLUGIN_NAME}" "${MEDIADIR}/logs"

CFG_FILE="${CFGDIR}/plugin.${PLUGIN_NAME}.json"
if [ ! -f "${CFG_FILE}" ]; then
cat > "${CFG_FILE}" << 'JSON'
{
  "enabled": true,
  "airplay_name": "FPP AirPlay Matrix",
  "model_name": "Matrix",
  "fps": 20,
  "flip_x": false,
  "flip_y": false,
  "uxplay_extra_args": ""
}
JSON
    chown ${FPPUSER}:${FPPGROUP} "${CFG_FILE}" 2>/dev/null || true
fi

setSetting restartFlag 1

echo "${PLUGIN_NAME} install complete"
