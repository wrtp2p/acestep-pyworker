#!/bin/bash
# Configure the official vastai/acestep image for serverless mode.
# Problems solved:
# 1. Supervisor logs to /dev/stdout → PyWorker needs a real file to tail
# 2. exit_portal.sh blocks startup (portal.yaml not configured in serverless mode)
# 3. New base images don't invoke start_server.sh → PyWorker must be started here

LOG_FILE="/var/log/ace-step-api.log"
PYWORKER_DIR="/workspace/vast-pyworker"
PYWORKER_VENV="/workspace/worker-env"
PYWORKER_LOG="/workspace/pyworker.log"

# --- 1. Fix ace-step-api: log to file, skip portal.yaml ---

cat > /etc/supervisor/conf.d/ace-step-api.conf << 'SUPERVISOR'
[program:ace-step-api]
environment=PROC_NAME="%(program_name)s"
command=/opt/supervisor-scripts/ace-step-api-serverless.sh
autostart=true
autorestart=true
exitcodes=0
startsecs=0
stopasgroup=true
killasgroup=true
stopsignal=TERM
stopwaitsecs=10
stdout_logfile=/var/log/ace-step-api.log
redirect_stderr=true
stdout_events_enabled=true
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=2
SUPERVISOR

cat > /opt/supervisor-scripts/ace-step-api-serverless.sh << 'SCRIPT'
#!/bin/bash
. /opt/supervisor-scripts/utils/environment.sh
. /venv/main/bin/activate

while [ -f "/.provisioning" ]; do
    echo "ace-step-api startup paused until provisioning completes"
    sleep 5
done

echo "Starting ACE Step API (serverless mode)"
cd "${WORKSPACE}/ACE-Step-1.5"
UV_PROJECT_ENVIRONMENT=/venv/main uv run acestep-api --port 8001
SCRIPT
chmod +x /opt/supervisor-scripts/ace-step-api-serverless.sh

# --- 2. Set up PyWorker (the new base images don't run start_server.sh) ---

# Install uv if not available
if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    [[ -f ~/.local/bin/env ]] && . ~/.local/bin/env
fi

# Clone pyworker repo
PYWORKER_REPO="${PYWORKER_REPO:-https://github.com/wrtp2p/acestep-pyworker.git}"
if [[ ! -d "$PYWORKER_DIR" ]]; then
    git clone "$PYWORKER_REPO" "$PYWORKER_DIR"
fi

# Create venv and install deps
if [[ ! -d "$PYWORKER_VENV" ]]; then
    uv venv --python-preference only-managed "$PYWORKER_VENV" -p 3.10
fi
. "$PYWORKER_VENV/bin/activate"
uv pip install -r "$PYWORKER_DIR/requirements.txt"
uv pip install vastai-sdk
deactivate

# Generate SSL cert for PyWorker (required by vastai-sdk)
WORKER_PORT="${WORKER_PORT:-3000}"
USE_SSL="${USE_SSL:-true}"
if [ "$USE_SSL" = "true" ] && [ ! -f /etc/instance.crt ]; then
    cat > /etc/openssl-san.cnf << 'SSLCONF'
[req]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = v3_req

[req_distinguished_name]
countryName         = US
stateOrProvinceName = CA
organizationName    = Vast.ai Inc.
commonName          = vast.ai

[v3_req]
basicConstraints = CA:FALSE
keyUsage         = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName   = @alt_names

[alt_names]
IP.1   = 0.0.0.0
SSLCONF

    openssl req -newkey rsa:2048 -subj "/C=US/ST=CA/CN=pyworker.vast.ai/" \
        -nodes -sha256 \
        -keyout /etc/instance.key \
        -out /etc/instance.csr \
        -config /etc/openssl-san.cnf 2>/dev/null

    if [ -n "$CONTAINER_ID" ]; then
        curl --header 'Content-Type: application/octet-stream' \
            --data-binary @/etc/instance.csr \
            -X POST "https://console.vast.ai/api/v0/sign_cert/?instance_id=$CONTAINER_ID" \
            > /etc/instance.crt 2>/dev/null
    fi
fi

# Add PyWorker as supervisor service
cat > /etc/supervisor/conf.d/pyworker.conf << SUPERVISOR
[program:pyworker]
environment=PROC_NAME="%(program_name)s"
command=/opt/supervisor-scripts/pyworker-serverless.sh
autostart=true
autorestart=true
startsecs=5
stopasgroup=true
killasgroup=true
stopsignal=TERM
stopwaitsecs=10
stdout_logfile=/workspace/pyworker.log
redirect_stderr=true
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=2
SUPERVISOR

cat > /opt/supervisor-scripts/pyworker-serverless.sh << SCRIPT
#!/bin/bash
. /opt/supervisor-scripts/utils/environment.sh
. ${PYWORKER_VENV}/bin/activate

while [ -f "/.provisioning" ]; do
    echo "pyworker startup paused until provisioning completes"
    sleep 5
done

echo "Starting PyWorker (serverless mode)"
cd ${PYWORKER_DIR}

export WORKER_PORT=\${WORKER_PORT:-3000}
export USE_SSL=\${USE_SSL:-true}
export REPORT_ADDR=\${REPORT_ADDR:-https://run.vast.ai}

python3 -m worker
SCRIPT
chmod +x /opt/supervisor-scripts/pyworker-serverless.sh

# --- 3. Apply all changes ---

supervisorctl reread
supervisorctl update

echo "Provisioning complete: ace-step-api → ${LOG_FILE}, pyworker → ${PYWORKER_LOG}"
