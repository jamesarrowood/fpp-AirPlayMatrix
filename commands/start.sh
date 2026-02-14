#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
MANAGER="${BASEDIR}/scripts/airplay_matrix_manager.sh"

if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo -n "${MANAGER}" start >/dev/null 2>&1 && exit 0
fi

"${MANAGER}" start
