# pfSense Backup Docker Container

This repository contains a minimal Docker image to automate **pfSense configuration backups** using a shell script. The container supports environment-based configuration, UID/GID assignment, and Swarm secrets for credentials.

---

## Features

- Back up multiple pfSense instances from a single container.
- Configurable backup directory and backup retention.
- Swarm secret support for storing credentials.
- Configurable backup directory and retention period
- Automatic pruning of old backups
- Runs as non-root user with configurable UID/GID
- Lightweight Alpine base image.

---

## Environment Variables

| Variable          | Default                | Description |
|-------------------|------------------------|-------------|
| SERVERS_FILE      | `/config/servers`      | Path to file or secret containing pfSense credentials (`FQDN:USERNAME:PASSWORD`) |
| BACKUP_DEST       | `/backup`              | Directory where backup output is stored |
| LOG_FILE          | `/var/log/backup.log`  | Persistent log file |
| EMAIL_ON_SUCCESS  | `false`                | Enable sending email when backup succeeds (`true`/`false`) |
| EMAIL_ON_FAILURE  | `false`                | Enable sending email when backup fails (`true`/`false`) |
| EMAIL_TO          | `admin@example.com`    | Recipient of status notifications |
| EMAIL_FROM        | `backup@example.com`   | Sender of status notifications |
| APP_NAME          | `pfSense`              | Application name in status notification |
| APP_BACKUP        | `/default.sh`          | Path to backup script executed by the container |
| KEEP_DAYS         | `30`                   | Number of days to retain backups |
| USER_UID          | `3000`                 | UID of backup user |
| USER_GID          | `3000`                 | GID of backup user |
| DRY_RUN           | `false`                | If `true`, backup logic logs actions but does not backup or prune anything |
| TZ                | `America/Chicago`      | Timezone used for timestamps |

---

## Swarm Secret Format

The servers file (used as a Swarm secret) should have one line per pfSense host:
```
FQDN:USERNAME:PASSWORD
```
For example:
```
pfsense.example.com:backupuser:securepass123
192.168.1.1:backupuser:anotherpass
```

---

## Docker Compose Example (Swarm)

```yaml
version: "3.9"

services:
  pfsense-backup:
    image: your-dockerhub-username/pfsense-backup:latest
    volumes:
      - /backup:/backup
    environment:
      BACKUP_DIR: /backup
      SERVERS_FILE: /run/secrets/pfsense-backup
      TZ: America/Chicago
      USER_UID: 3000
      USER_GID: 3000
      KEEP_DAYS: 30
    secrets:
      - pfsense-backup
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: none

secrets:
  pfsense-backup:
    external: true
```

### Usage

1. Create the Swarm secret:
```bash
docker secret create pfsense-backup ./servers
```
2. Deploy the stack:
```bash
docker stack deploy -c docker-compose.yml pfsense-backup_stack
```

---

## Local Testing

For testing without Swarm, you can mount the servers file and run the container directly:
```bash
docker run -it --rm \
  -v /backup:/backup \
  -v ./servers:/config/servers \
  -e SCRIPT_NAME=pfsense-backup.sh \
  your-dockerhub-username/pfsense-backup:latest
```

---

## Notes

- UID/GID customization ensures that backup files match host file ownership.
- Backup retention is controlled via `KEEP_DAYS`.
- The container uses `su-exec` to drop privileges to the backup user.

---
