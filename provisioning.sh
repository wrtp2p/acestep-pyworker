#!/bin/bash
# Configure the official vastai/acestep image for serverless mode:
# 1. Redirect ace-step-api supervisor logs to a file (PyWorker needs a real file to tail)
# 2. Ensure portal.yaml includes ACE Step API (serverless mode skips portal setup)

LOG_FILE="/var/log/ace-step-api.log"

# Ensure portal.yaml exists and includes ACE Step API so exit_portal.sh doesn't skip it
if [ ! -f /etc/portal.yaml ]; then
    echo "ACE Step API:" > /etc/portal.yaml
elif ! grep -qi "ACE Step API" /etc/portal.yaml; then
    echo "ACE Step API:" >> /etc/portal.yaml
fi

# Redirect supervisor logs to a file for PyWorker log tailing
sed -i "s|stdout_logfile=/dev/stdout|stdout_logfile=${LOG_FILE}|" /etc/supervisor/conf.d/ace-step-api.conf
sed -i "s|stdout_logfile_maxbytes=0|stdout_logfile_maxbytes=50MB|" /etc/supervisor/conf.d/ace-step-api.conf

# Apply the config change (supervisor is already running at this point)
supervisorctl reread
supervisorctl update

echo "Provisioning complete: ace-step-api logs → ${LOG_FILE}, portal.yaml updated"
