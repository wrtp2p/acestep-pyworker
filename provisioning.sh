#!/bin/bash
# Redirect ace-step-api supervisor logs to a file so PyWorker can tail them.
# The official vastai/acestep image logs to /dev/stdout by default,
# but PyWorker needs a real file to monitor for startup signals.

LOG_FILE="/var/log/ace-step-api.log"

sed -i "s|stdout_logfile=/dev/stdout|stdout_logfile=${LOG_FILE}|" /etc/supervisor/conf.d/ace-step-api.conf
sed -i "s|stdout_logfile_maxbytes=0|stdout_logfile_maxbytes=50MB|" /etc/supervisor/conf.d/ace-step-api.conf

# Apply the config change (supervisor is already running at this point)
supervisorctl reread
supervisorctl update

echo "Provisioning complete: ace-step-api logs redirected to ${LOG_FILE}"
