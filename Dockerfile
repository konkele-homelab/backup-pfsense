ARG UPSTREAM_TAG=latest
FROM registry.lab.konkel.us/backup-base:${UPSTREAM_TAG}

# pfSense Backup Script
ARG SCRIPT_FILE=backup-pfsense.sh

# Install Application Specific Backup Script
ENV APP_BACKUP=/config/${SCRIPT_FILE}
COPY ${SCRIPT_FILE} ${APP_BACKUP}
RUN chmod +x ${APP_BACKUP}
