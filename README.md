# pfSense Backup Docker Container

This repository contains a minimal Docker image to automate **pfSense configuration backups** using a shell script. The container supports environment-based configuration, UID/GID assignment, Swarm secrets for credentials, and flexible retention policies.

---

## Features

- Back up multiple pfSense instances from a single container.
- Configurable backup directory and pluggable retention policies: **GFS, FIFO, Calendar**.
- Swarm secret support for storing credentials.
- Automatic pruning of old backups according to retention policy.
- Runs as non-root user with configurable UID/GID.
- Lightweight Alpine base image.

---

## Retention Policies

- **GFS (Grandfather-Father-Son)**: Retain daily, weekly, and monthly snapshots.
- **FIFO (First-In-First-Out)**: Keep a fixed number of most recent backups.
- **Calendar**: Keep backups for a fixed number of days.

Retention behavior is controlled via environment variables.

---

## Environment Variables

| Variable            | Default                             | Description |
|---------------------|-------------------------------------|-------------|
| SERVERS_FILE        | `/config/servers`                   | Path to file or secret containing pfSense credentials (`FQDN:USERNAME:PASSWORD`) |
| BACKUP_DEST         | `/backup`                           | Directory where backup output is stored |
| LOG_FILE            | `/var/log/backup.log`               | Persistent log file |
| RETENTION_POLICY    | `gfs`                               | Retention policy: `gfs`, `fifo`, or `calendar` |
| GFS_DAILY           | `7`                                 | Number of daily backups to keep (GFS only) |
| GFS_WEEKLY          | `4`                                 | Number of weekly backups to keep (GFS only) |
| GFS_MONTHLY         | `6`                                 | Number of monthly backups to keep (GFS only) |
| FIFO_COUNT          | `14`                                | Number of backups to keep (FIFO only) |
| CALENDAR_DAYS       | `30`                                | Number of days to keep backups (Calendar only) |
| EMAIL_ON_SUCCESS    | `false`                             | Enable sending email on success (`true`/`false`) |
| EMAIL_ON_FAILURE    | `false`                             | Enable sending email on failure (`true`/`false`) |
| EMAIL_TO            | `admin@example.com`                 | Recipient of status notifications |
| EMAIL_FROM          | `backup@example.com`                | Sender of status notifications |
| APP_NAME            | `pfSense`                           | Application name in status notifications |
| APP_BACKUP          | `/usr/local/bin/backup-pfsense.sh`  | Path to backup script executed by the container |
| USER_UID            | `3000`                              | UID of backup user |
| USER_GID            | `3000`                              | GID of backup user |
| DRY_RUN             | `false`                             | If `true`, backup logic logs actions but does not backup or prune anything |
| TZ                  | `America/Chicago`                   | Timezone used for timestamps |

---

## Swarm Secret Format

The servers file (used as a Swarm secret) should have one line per pfSense host:

```
FQDN:USERNAME:PASSWORD
```

Example:

```
pfsense.example.com:backupuser:securepass123
192.168.1.1:backupuser:anotherpass
```

---

## Docker Compose Example (Swarm)

```yaml
version: "3.9"

services:
  backup-pfsense:
    image: your-dockerhub-username/backup-pfsense:latest
    environment:
      BACKUP_DEST: /backup
      SERVERS_FILE: /run/secrets/backup-pfsense
      RETENTION_POLICY: gfs
      GFS_DAILY: 7
      GFS_WEEKLY: 4
      GFS_MONTHLY: 6
      EMAIL_ON_FAILURE: "true"
      EMAIL_TO: admin@example.com
      DRY_RUN: "false"
      TZ: America/Chicago
      USER_UID: 3000
      USER_GID: 3000
    volumes:
      - /backup:/backup
    secrets:
      - backup-pfsense
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: none

secrets:
  backup-pfsense:
    external: true
```

---

## Local Testing

For testing without Swarm, mount the servers file and run the container directly:

```bash
docker run -it --rm \
  -v /backup:/backup \
  -v ./servers:/config/servers \
  -e APP_BACKUP=/backup-pfsense.sh \
  -e RETENTION_POLICY=gfs \
  -e DRY_RUN=true \
  your-dockerhub-username/backup-pfsense:latest
```

Change `RETENTION_POLICY` to `fifo` or `calendar` to test other modes.

---

## Notes

- UID/GID customization ensures backup files match host file ownership.
- Retention is controlled via `RETENTION_POLICY` and corresponding variables (`GFS_DAILY`, `FIFO_COUNT`, `CALENDAR_DAYS`).
- `DRY_RUN=true` is useful for testing retention and backup logic without modifying files.
- Backup logic is implemented in `backup_common.sh` and sourced by `backup.sh`.
- The container uses `su-exec` to drop privileges to the backup user.
