#!/bin/sh
set -eu

# ----------------------
# Default variables
# ----------------------
: "${APP_NAME:=pfSense}"
: "${SERVERS_FILE:=/config/servers}"
: "${PROTO:=https}"
: "${DRY_RUN:=false}"

export APP_NAME

# ----------------------
# Logging helpers (from wrapper)
# ----------------------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${RUN_LOG:-/tmp/backup_run.log}"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${RUN_LOG:-/tmp/backup_run.log}" >&2; }

# ----------------------
# CSRF Extraction Helper
# ----------------------
extract_csrf() {
    grep "__csrf_magic" \
    | tr '\n' ' ' \
    | sed "s/.*name=['\"]__csrf_magic['\"][^>]*value=['\"]\([^'\"]*['\"]\).*/\1/" \
    | tr -d "'\""
}

# ----------------------
# pfSense Backup Function
# ----------------------
pfsense_backup() {
    host="$1"
    user="$2"
    pass="$3"

    backup_file="${SNAPSHOT_DIR}/${host}.xml"
    serverURL="${PROTO}://${host}"

    [ "$DRY_RUN" != "true" ] && mkdir -p "$SNAPSHOT_DIR"

    log "Starting pfSense backup for $host -> $backup_file"

    tempdir=$(mktemp -d)
    cookiejar="$tempdir/cookies.txt"
    trap 'rm -rf "$tempdir"' EXIT

    # Fetch CSRF #1
    csrf1=$(curl -sk -L -c "$cookiejar" --max-time 30 --retry 3 "${serverURL}/diag_backup.php" | extract_csrf)
    [ -n "$csrf1" ] || { log_error "$host: CSRF #1 not found"; return 1; }

    # Login and fetch CSRF #2
    csrf2=$(curl -sk -L -b "$cookiejar" -c "$cookiejar" --max-time 30 --retry 3 \
        --data "login=Login&usernamefld=${user}&passwordfld=${pass}&__csrf_magic=${csrf1}" \
        "${serverURL}/diag_backup.php" \
        | extract_csrf)
    [ -n "$csrf2" ] || { log_error "$host: Login failed / CSRF #2 missing"; return 1; }

    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY RUN] Would download backup for $host to $backup_file"
        return 0
    fi

    # Download backup
    curl -sk -L -b "$cookiejar" --max-time 60 --retry 3 \
        --data "download=download&donotbackuprrd=yes&__csrf_magic=${csrf2}" \
        "${serverURL}/diag_backup.php" \
        -o "$backup_file" || { log_error "$host: Backup download failed"; return 1; }

    # Validate output
    [ -s "$backup_file" ] || { log_error "$host: Backup file empty"; rm -f "$backup_file"; return 1; }
    root_tag=$(grep -o '<[a-zA-Z0-9_-]\+' "$backup_file" | grep -v '^<?xml' | head -n1 | tr -d '<')
    [ "$root_tag" = "pfsense" ] || { log_error "$host: Invalid XML root <$root_tag>"; rm -f "$backup_file"; return 1; }

    chmod 600 "$backup_file"
    log "Backup completed for $host: $backup_file"
}

# ----------------------
# Backup Execution
# ----------------------
[ -f "$SERVERS_FILE" ] || { log_error "Servers file missing: $SERVERS_FILE"; exit 1; }

while IFS=: read -r host user pass || [ -n "$host" ]; do
    [ -z "$host" ] && continue
    [ -n "$user" ] || { log_error "$host: Missing username"; continue; }
    [ -n "$pass" ] || { log_error "$host: Missing password"; continue; }

    pfsense_backup "$host" "$user" "$pass"
done < "$SERVERS_FILE"

