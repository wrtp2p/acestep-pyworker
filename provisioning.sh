#!/bin/bash
# Configure the official vastai/acestep image for serverless mode.
# Problems solved:
# 1. Supervisor logs to /dev/stdout → PyWorker needs a real file to tail
# 2. exit_portal.sh blocks startup (portal.yaml not configured in serverless mode)

LOG_FILE="/var/log/ace-step-api.log"

# Replace supervisor config: log to file + use a simple startup script
# that skips the portal.yaml check (not needed in serverless mode)
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

# Create a serverless-friendly startup script (no portal.yaml check)
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

# Apply changes
supervisorctl reread
supervisorctl update

echo "Provisioning complete: serverless ace-step-api → ${LOG_FILE}"
