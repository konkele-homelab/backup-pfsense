#!/bin/sh
set -eu

# ----------------------
# Default variables
# ----------------------
: "${APP_NAME:=pfSense}"
: "${SERVERS_FILE:=/config/servers}"
: "${PROTO:=https}"
: "${SNAPSHOT_DIR:?SNAPSHOT_DIR not set by wrapper}"

export APP_NAME

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
    (
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

        # Validate file is not empty
        [ -s "$backup_file" ] || {
            log_error "$host: Backup file empty"
            rm -f "$backup_file"
            return 1
        }

        # Ensure this is a pfSense config XML
        grep -q '<pfsense>' "$backup_file" || {
            log_error "$host: Invalid pfSense XML (missing <pfsense> root)"
            rm -f "$backup_file"
            return 1
        }

        chmod 600 "$backup_file"
        log "Backup completed for $host: $backup_file"
    )
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

# ----------------------
# Debug: keep container running
# ----------------------
if [ "${DEBUG:-false}" = "true" ]; then
    log "DEBUG mode enabled — container will remain running."
    tail -f /dev/null
fi