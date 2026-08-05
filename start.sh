#!/usr/bin/env bash
set -uo pipefail

readonly COMFYUI_DIR="/opt/ComfyUI"
readonly COMFYUI_PID_FILE="/run/comfyui.pid"
readonly FILEBROWSER_DATABASE="/run/filebrowser.db"

# Preserve the base image's CUDA-specific Torch pins for packages installed by
# ComfyUI Manager while the disposable Pod is running.
export PIP_CONSTRAINT="/opt/comfyui-runtime-constraints.txt"

comfyui_pid=""
filebrowser_pid=""
nginx_pid=""
stopping=0

log() {
    printf '[startup] %s\n' "$*"
}

stop_container() {
    stopping=1
    log "Stopping services..."

    if [[ -n "${comfyui_pid}" ]] && kill -0 "${comfyui_pid}" 2>/dev/null; then
        kill -TERM "${comfyui_pid}" 2>/dev/null || true
    fi
    if [[ -n "${filebrowser_pid}" ]] && kill -0 "${filebrowser_pid}" 2>/dev/null; then
        kill -TERM "${filebrowser_pid}" 2>/dev/null || true
    fi
    if [[ -n "${nginx_pid}" ]] && kill -0 "${nginx_pid}" 2>/dev/null; then
        kill -TERM "${nginx_pid}" 2>/dev/null || true
    fi
    if [[ -f /run/sshd.pid ]]; then
        kill -TERM "$(cat /run/sshd.pid)" 2>/dev/null || true
    fi
}

trap stop_container TERM INT

# RunPod supplies PUBLIC_KEY when SSH is enabled for a Pod.
if [[ -n "${PUBLIC_KEY:-}" ]]; then
    install -d -m 0700 /root/.ssh
    printf '%s\n' "${PUBLIC_KEY}" > /root/.ssh/authorized_keys
    chmod 0600 /root/.ssh/authorized_keys
fi

mkdir -p /run/sshd
ssh-keygen -A
/usr/sbin/sshd
log "SSH is listening on port 22."

# The database is intentionally ephemeral. Restrict the browser root to the
# disposable ComfyUI tree, including its models, custom_nodes, input and output.
if [[ -n "${WEBUI_PASSWORD:-}" ]]; then
    # Initialise a fresh File Browser database with admin credentials.
    filebrowser config init --database "${FILEBROWSER_DATABASE}"
    filebrowser users add admin "${WEBUI_PASSWORD}" \
        --database "${FILEBROWSER_DATABASE}" \
        --perm.admin
    filebrowser \
        --database "${FILEBROWSER_DATABASE}" \
        --root "${COMFYUI_DIR}" \
        --address 0.0.0.0 \
        --port 8080 &
else
    filebrowser \
        --database "${FILEBROWSER_DATABASE}" \
        --root "${COMFYUI_DIR}" \
        --address 0.0.0.0 \
        --port 8080 \
        --noauth &
fi
filebrowser_pid=$!
log "File Browser is listening on port 8080."

# When a password is set, expose ComfyUI through an nginx basic-auth proxy on
# port 8189. ComfyUI itself stays on 8188 (internal only in that mode).
if [[ -n "${WEBUI_PASSWORD:-}" ]]; then
    htpasswd -bc /run/comfyui.htpasswd admin "${WEBUI_PASSWORD}"
    cat > /run/nginx-comfyui.conf <<'NGINX_EOF'
events {}
http {
    server {
        listen 8189;
        location / {
            auth_basic            "ComfyUI";
            auth_basic_user_file  /run/comfyui.htpasswd;

            proxy_pass            http://127.0.0.1:8188;
            proxy_http_version    1.1;
            proxy_set_header      Upgrade    $http_upgrade;
            proxy_set_header      Connection "upgrade";
            proxy_set_header      Host       $host;
            proxy_read_timeout    3600s;
        }
    }
}
NGINX_EOF
    nginx -c /run/nginx-comfyui.conf &
    nginx_pid=$!
    log "nginx ComfyUI proxy (basic-auth) is listening on port 8189."
fi

extra_args=()
if [[ -n "${COMFYUI_EXTRA_ARGS:-}" ]]; then
    # This environment variable is intended for ordinary whitespace-separated
    # ComfyUI flags, for example: --preview-method auto
    read -r -a extra_args <<< "${COMFYUI_EXTRA_ARGS}"
fi

# Keep PID 1 alive so restart-comfy can terminate only ComfyUI. A clean exit or
# crash is restarted automatically; stdout/stderr remain attached to Pod logs.
while (( stopping == 0 )); do
    log "Starting ComfyUI from ${COMFYUI_DIR} on port 8188."
    (
        cd "${COMFYUI_DIR}"
        exec /usr/bin/python3.12 -u /opt/ComfyUI/main.py \
            --listen 0.0.0.0 \
            --port 8188 \
            --enable-manager \
            "${extra_args[@]}"
    ) &
    comfyui_pid=$!
    printf '%s\n' "${comfyui_pid}" > "${COMFYUI_PID_FILE}"

    wait "${comfyui_pid}"
    comfyui_status=$?
    rm -f "${COMFYUI_PID_FILE}"
    comfyui_pid=""

    if (( stopping != 0 )); then
        break
    fi

    log "ComfyUI exited with status ${comfyui_status}; restarting in 2 seconds."
    sleep 2 &
    wait $! || true
done

wait 2>/dev/null || true
log "Container stopped."
