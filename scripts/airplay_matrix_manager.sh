#!/bin/bash

set -u

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
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    PLUGIN_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
fi

TMP_DIR="${MEDIADIR}/tmp/${PLUGIN_NAME}"
LOG_FILE="${MEDIADIR}/logs/${PLUGIN_NAME}.log"
CFG_FILE="${MEDIADIR}/config/plugin.${PLUGIN_NAME}.json"
DAEMON="${PLUGIN_DIR}/scripts/airplay_matrixd.py"

init_runtime_paths() {
    mkdir -p "${TMP_DIR}" "${MEDIADIR}/logs" >/dev/null 2>&1 || true

    if [ ! -d "${TMP_DIR}" ] || [ ! -w "${TMP_DIR}" ]; then
        TMP_DIR="/tmp/${PLUGIN_NAME}"
        mkdir -p "${TMP_DIR}" >/dev/null 2>&1 || true
    fi

    PID_FILE="${TMP_DIR}/daemon.pid"

    if ! touch "${LOG_FILE}" >/dev/null 2>&1; then
        LOG_FILE="${TMP_DIR}/${PLUGIN_NAME}.log"
        touch "${LOG_FILE}" >/dev/null 2>&1 || true
    fi
}

init_runtime_paths

can_sudo_nopass() {
    if ! command -v sudo >/dev/null 2>&1; then
        return 1
    fi
    sudo -n true >/dev/null 2>&1
}

pid_is_alive() {
    local pid="$1"
    if kill -0 "${pid}" 2>/dev/null; then
        return 0
    fi
    if can_sudo_nopass && sudo -n kill -0 "${pid}" 2>/dev/null; then
        return 0
    fi
    return 1
}

kill_pid() {
    local sig="$1"
    local pid="$2"
    if kill "-${sig}" "${pid}" 2>/dev/null; then
        return 0
    fi
    if can_sudo_nopass && sudo -n kill "-${sig}" "${pid}" 2>/dev/null; then
        return 0
    fi
    return 1
}

is_running() {
    if [ ! -f "${PID_FILE}" ]; then
        return 1
    fi

    local pid
    pid=$(cat "${PID_FILE}" 2>/dev/null)
    if [ -z "${pid}" ]; then
        return 1
    fi

    pid_is_alive "${pid}"
}

read_cfg_field() {
    local field="$1"

    if [ ! -f "${CFG_FILE}" ]; then
        if [ "${field}" = "airplay_name" ]; then
            echo "FPP AirPlay Matrix"
            return
        fi
        if [ "${field}" = "model_name" ]; then
            echo "Matrix"
            return
        fi
        echo ""
        return
    fi

    python3 - "$CFG_FILE" "$field" << 'PY'
import json
import sys

cfg_file = sys.argv[1]
field = sys.argv[2]

defaults = {
    "airplay_name": "FPP AirPlay Matrix",
    "model_name": "Matrix",
}

try:
    with open(cfg_file, "r", encoding="utf-8") as f:
        cfg = json.load(f)
except Exception:
    cfg = {}

val = cfg.get(field, defaults.get(field, ""))
if isinstance(val, bool):
    print("true" if val else "false")
else:
    print(str(val))
PY
}

status_json() {
    local running="false"
    local pid="null"

    if is_running; then
        running="true"
        pid=$(cat "${PID_FILE}")
    fi

    local airplay_name
    local model_name
    airplay_name=$(read_cfg_field "airplay_name")
    model_name=$(read_cfg_field "model_name")

    python3 - "$running" "$pid" "$airplay_name" "$model_name" << 'PY'
import json
import sys

running = sys.argv[1].lower() == "true"
pid_raw = sys.argv[2]
airplay_name = sys.argv[3]
model_name = sys.argv[4]

pid = None
try:
    pid = int(pid_raw)
except Exception:
    pid = None

print(json.dumps({
    "running": running,
    "pid": pid,
    "airplay_name": airplay_name,
    "model_name": model_name,
    "message": ""
}))
PY
}

start_daemon() {
    if is_running; then
        echo "Already running (PID $(cat "${PID_FILE}"))"
        return 0
    fi

    if [ ! -x "${DAEMON}" ]; then
        chmod +x "${DAEMON}" 2>/dev/null
    fi

    local launch_cmd=()
    if [ "$(id -u)" -ne 0 ] && can_sudo_nopass; then
        launch_cmd=(sudo -n -E)
    fi

    nohup "${launch_cmd[@]}" python3 "${DAEMON}" --config "${CFG_FILE}" --media-dir "${MEDIADIR}" --plugin-dir "${PLUGIN_DIR}" >> "${LOG_FILE}" 2>&1 &
    echo $! > "${PID_FILE}"

    sleep 1
    if is_running; then
        echo "Started (PID $(cat "${PID_FILE}"))"
        return 0
    fi

    echo "Failed to start daemon. Check ${LOG_FILE}"
    rm -f "${PID_FILE}"
    return 1
}

stop_daemon() {
    local stopped=0

    if is_running; then
        local pid
        pid=$(cat "${PID_FILE}")
        kill_pid "TERM" "${pid}" || true

        local i
        for i in 1 2 3 4 5; do
            if pid_is_alive "${pid}"; then
                sleep 1
            else
                stopped=1
                break
            fi
        done

        if pid_is_alive "${pid}"; then
            kill_pid "KILL" "${pid}" || true
        fi
    else
        stopped=1
    fi

    rm -f "${PID_FILE}"

    # Cleanup any orphaned instances
    pkill -f "airplay_matrixd.py" >/dev/null 2>&1 || true
    if can_sudo_nopass; then
        sudo -n pkill -f "airplay_matrixd.py" >/dev/null 2>&1 || true
    fi

    if [ "${stopped}" -eq 1 ]; then
        echo "Stopped"
    else
        echo "Stopped"
    fi

    return 0
}

case "${1:-status}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        start_daemon
        ;;
    status)
        if is_running; then
            echo "running"
            exit 0
        else
            echo "stopped"
            exit 1
        fi
        ;;
    status-json)
        status_json
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|status-json}"
        exit 2
        ;;
esac
