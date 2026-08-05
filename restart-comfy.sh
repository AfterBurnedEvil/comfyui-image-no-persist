#!/usr/bin/env bash
set -euo pipefail

readonly PID_FILE="/run/comfyui.pid"

if [[ ! -s "${PID_FILE}" ]]; then
    echo "ComfyUI PID file not found; it may still be starting." >&2
    exit 1
fi

old_pid="$(cat "${PID_FILE}")"
if [[ ! "${old_pid}" =~ ^[0-9]+$ ]] || ! kill -0 "${old_pid}" 2>/dev/null; then
    echo "ComfyUI is not running (stale PID file: ${old_pid})." >&2
    exit 1
fi

if ! tr '\0' ' ' < "/proc/${old_pid}/cmdline" | grep -Fq '/opt/ComfyUI/main.py'; then
    echo "Refusing to stop PID ${old_pid}: it is not the managed ComfyUI process." >&2
    exit 1
fi

echo "Stopping ComfyUI (PID ${old_pid})..."
kill -TERM "${old_pid}"

for _ in $(seq 1 60); do
    if [[ -s "${PID_FILE}" ]]; then
        new_pid="$(cat "${PID_FILE}")"
        if [[ "${new_pid}" =~ ^[0-9]+$ ]] \
            && [[ "${new_pid}" != "${old_pid}" ]] \
            && kill -0 "${new_pid}" 2>/dev/null; then
            echo "ComfyUI restarted (PID ${new_pid})."
            exit 0
        fi
    fi
    sleep 0.5
done

echo "Timed out waiting for ComfyUI to restart; inspect the container logs." >&2
exit 1

