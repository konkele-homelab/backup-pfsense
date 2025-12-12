#!/bin/sh
set -eu

# ----------------------
# Default variables
# ----------------------
: "${APP_NAME:=pfSense}"
: "${BACKUP_DEST:=/backup}"
: "${KEEP_DAYS:=30}"
: "${DRY_RUN:=false}"
: "${TZ:=America/Chicago}"
: "${TIMESTAMP:=$(date +%Y%m%d-%H%M%S)}"

: "${SERVERS_FILE:=/config/servers}"
: "${PROTO:=https}"

export APP_NAME
# ----------------------
# pfSense Backup
# ----------------------
pfsense_backup() {
    host="$1"
    user="$2"
    pass="$3"

    backup="${BACKUP_DEST}/${host}-${TIMESTAMP}.xml"
    serverURL="${PROTO}://${host}"

    mkdir -p "$BACKUP_DEST"
    log "Starting backup for ${host}"

    tempdir=$(mktemp -d)
    cookiejar="$tempdir/cookies.txt"

    # Cleanup tempdir on exit
    trap 'rm -rf "$tempdir"' EXIT

    # Fetch CSRF #1
    csrf_magic1=$(curl -sk -L -c "$cookiejar" --max-time 30 --retry 3 "${serverURL}/diag_backup.php" | extract_csrf)

    if [ -z "$csrf_magic1" ]; then
        log_error "CSRF #1 not found for ${host}"
        return 1
    fi

    # Login and fetch CSRF #2
    csrf_magic2=$(
        curl -sk -L -b "$cookiejar" -c "$cookiejar" --max-time 30 --retry 3 \
            --data "login=Login&usernamefld=${user}&passwordfld=${pass}&__csrf_magic=${csrf_magic1}" \
            "${serverURL}/diag_backup.php" \
        | extract_csrf
    )

    if [ -z "$csrf_magic2" ]; then
        log_error "Login failed or CSRF #2 missing for ${host}"
        return 1
    fi

    # Dry run
    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY RUN] Would perform backup for ${host}, saving to ${backup}"
        return 0
    fi

    # Request configuration backup
    curl -sk -L -b "$cookiejar" --max-time 60 --retry 3 \
        --data "download=download&donotbackuprrd=yes&__csrf_magic=${csrf_magic2}" \
        "${serverURL}/diag_backup.php" \
        -o "$backup" || {
            log_error "Backup download failed for ${host}"
            return 1
        }

    # Validate output file is not empty
    if [ ! -s "$backup" ]; then
        log_error "${host}: Backup file missing or empty"
        rm -f "$backup"
        return 1
    fi

    # Validate XML root element is <pfsense>
    root_tag=$(grep -o '<[a-zA-Z0-9_-]\+' "$backup" | grep -v '^<?xml' | head -n1 | tr -d '<')
    if [ "$root_tag" != "pfsense" ]; then
        log_error "${host}: Backup XML root is invalid (expected <pfsense>, got <$root_tag>)"
        rm -f "$backup"
        return 1
    fi

    # Secure file
    chmod 600 "$backup"

    log "Backup saved: ${backup}"

    return 0
}

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
# Backup Execution
# ----------------------
if [ ! -f "$SERVERS_FILE" ]; then
    log_error "Servers file not found: ${SERVERS_FILE}"
    exit 1
fi

# Read server list line by line
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines
    [ -z "$line" ] && continue

    # Split host and API key using POSIX tools
    host=$(echo "$line" | awk -F: '{print $1}')
    user=$(echo "$line" | awk -F: '{print $2}')
    pass=$(echo "$line" | awk -F: '{print $3}')

    if [ -z "$host" ] || [ -z "$user" ] || [ -z "$pass" ]; then
        log_error "Invalid entry in servers file: ${line}"
        continue
    fi

    # Run backup
    pfsense_backup "$host" "$user" "$pass"

    # Prune old backups
    prune_by_timestamp "${host}-*" "$KEEP_DAYS" "$BACKUP_DEST"

done < "$SERVERS_FILE"

# ----------------------
# Debug: keep container running
# ----------------------
if [ "${DEBUG:-false}" = "true" ]; then
    log "DEBUG mode enabled — container will remain running."
    tail -f /dev/null
fi
