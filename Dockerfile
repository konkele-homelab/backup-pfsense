# Default Arguments for Upstream Base Image
ARG UPSTREAM_REGISTRY=registry.lab.konkel.us
ARG UPSTREAM_REPO=backup-base
ARG UPSTREAM_TAG=latest

# Use Upstream Base Image
FROM ${UPSTREAM_REGISTRY}/${UPSTREAM_REPO}:${UPSTREAM_TAG}

# App Specific Backup Script
ARG SCRIPT_FILE=backup-pfsense.sh

# Install Application Specific Backup Script
ENV APP_BACKUP=/usr/local/bin/${SCRIPT_FILE}
COPY ${SCRIPT_FILE} ${APP_BACKUP}
RUN chmod +x ${APP_BACKUP}
