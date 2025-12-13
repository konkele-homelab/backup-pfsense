# pfSense Backup Docker Container

This repository contains a minimal Docker image to automate **pfSense configuration backups** using a shell script. The container supports environment-based configuration, UID/GID assignment, Swarm secrets for credentials, SMTP notifications, and flexible retention policies.

---

## Features

- Back up multiple pfSense instances from a single container.
- Creates a **single timestamped snapshot directory per run** containing all host backups.
- Swarm secret support for storing credentials.
- Pluggable backup retention policies: **GFS**, **FIFO**, **Calendar**.
- Automatic creation of daily, weekly, and monthly snapshots (for GFS).
- Runs as non-root user with configurable UID/GID.
- Lightweight Alpine base image.
- Email notifications on success and/or failure.
- **DRY-RUN mode** for safe testing without modifying data.

---

## Retention Policies

- **GFS (Grandfather-Father-Son)**: Retain daily, weekly, and monthly snapshots.
- **FIFO (First-In-First-Out)**: Keep a fixed number of most recent snapshots.
- **Calendar**: Keep snapshots for a fixed number of days.

Retention behavior is controlled via environment variables and operates on **snapshot directories**, not individual files.

---

## Directory Layout

Backups are organized into timestamped snapshot directories:

```
/backup/
└── daily/
    ├── 2025-12-13_13-36-47/
    │   ├── pfsense1.example.com.xml
    │   └── pfsense2.example.com.xml
    ├── 2025-12-12_13-30-01/
    └── ...
└── weekly/
└── monthly/
└── latest -> daily/2025-12-13_13-36-47
```

- Each container run creates **one snapshot directory** shared by all hosts.
- Retention policies prune entire snapshot directories.
- The `latest` symlink always points to the most recent successful run.

---

## Environment Variables

| Variable            | Default                                | Description |
|---------------------|----------------------------------------|-------------|
| APP_NAME            | `pfSense`                              | Application name used in status notifications |
| APP_BACKUP          | `/usr/local/bin/backup-pfsense.sh`     | Path to application backup script |
| PROTO               | `https`                                | Protocol used to contact pfSense (`http` / `https`) |
| SERVERS_FILE        | `/config/servers`                      | File or secret containing pfSense credentials (`FQDN:USERNAME:PASSWORD`) |
| BACKUP_DEST         | `/backup`                              | Directory where backup output is stored |
| DRY_RUN             | `false`                                | If `true`, logs actions but does not write or prune backups |
| LOG_FILE            | `/var/log/backup.log`                  | Persistent log file |
| EMAIL_ON_SUCCESS    | `false`                                | Send email when backup succeeds |
| EMAIL_ON_FAILURE    | `false`                                | Send email when backup fails |
| EMAIL_TO            | `admin@example.com`                    | Recipient of status notifications |
| EMAIL_FROM          | `backup@example.com`                   | Sender address for email notifications |
| SMTP_SERVER         | `smtp.example.com`                     | SMTP server hostname or IP |
| SMTP_PORT           | `25`                                   | SMTP server port |
| SMTP_TLS            | `off`                                  | Enable TLS (`off` / `on`) |
| SMTP_USER           | *(empty)*                              | SMTP username |
| SMTP_USER_FILE      | *(empty)*                              | File or secret containing SMTP username |
| SMTP_PASS           | *(empty)*                              | SMTP password |
| SMTP_PASS_FILE      | *(empty)*                              | File or secret containing SMTP password |
| RETENTION_POLICY    | `gfs`                                  | Retention strategy: `gfs`, `fifo`, or `calendar` |
| GFS_DAILY           | `7`                                    | Number of daily snapshots to keep (GFS) |
| GFS_WEEKLY          | `4`                                    | Number of weekly snapshots to keep (GFS) |
| GFS_MONTHLY         | `6`                                    | Number of monthly snapshots to keep (GFS) |
| FIFO_COUNT          | `14`                                   | Number of snapshots to retain (FIFO) |
| CALENDAR_DAYS       | `30`                                   | Number of days to retain snapshots (Calendar) |
| TZ                  | `America/Chicago`                      | Timezone used for timestamps |
| USER_UID            | `3000`                                 | UID of backup user |
| USER_GID            | `3000`                                 | GID of backup user |
| DEBUG               | `false`                                | If `true`, container remains running after backup |

---

## Swarm Secret Format

The servers file (typically stored as a Docker Swarm secret) must contain one host per line:

```
FQDN:USERNAME:PASSWORD
```

Example:

```
pfsense.example.com:backupuser:securepass123
192.168.1.1:backupuser:anotherpass
```

> **Security Note**  
> The servers file contains plaintext credentials. Always store it as a Docker secret or restrict file permissions appropriately.

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
      SMTP_SERVER: smtp.example.com
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

To test without Swarm:

```bash
docker run -it --rm \
  -v /backup:/backup \
  -v ./servers:/config/servers \
  -e APP_BACKUP=/usr/local/bin/backup-pfsense.sh \
  -e RETENTION_POLICY=gfs \
  -e DRY_RUN=true \
  your-dockerhub-username/backup-pfsense:latest
```

Change `RETENTION_POLICY` to `fifo` or `calendar` to test other modes.

---

## Failure Semantics

- If **any host backup fails**, the application script exits non-zero.
- On failure:
  - The snapshot directory is preserved for inspection.
  - Retention policies are **not applied**.
  - Failure notifications are sent if enabled.

---

## Logging

- Logs each backup start, completion, and file paths.
- Logs pruning actions according to the selected retention policy.
- Errors are written to `stderr`.

---

## Notes

- Backup files are validated to ensure they contain a valid `<pfsense>` XML root before being accepted.
- UID/GID customization ensures backup files match host filesystem ownership.
- Pluggable retention policies allow flexible backup management:
  - **GFS**: Daily/weekly/monthly snapshots with `latest` symlink.
  - **FIFO**: Keeps only the last `FIFO_COUNT` snapshots.
  - **Calendar**: Keeps all snapshots for a specified number of days.
- Use `DRY_RUN=true` to safely test backup and retention behavior without modifying files.
