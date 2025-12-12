#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Configuration / environment
############################################

# Optional test mode:
# - When SKIP_S3_UPLOAD=true we run cluster-backup.sh
#   and stop after verifying files exist on the host.
SKIP_S3_UPLOAD="${SKIP_S3_UPLOAD:-false}"

# Only require S3 vars when we actually want to upload
if [[ "${SKIP_S3_UPLOAD}" != "true" ]]; then
  : "${S3_ENDPOINT:?S3_ENDPOINT is required, e.g. https://s3.ca-central-1.amazonaws.com}"
  : "${S3_BUCKET:?S3_BUCKET is required}"
  : "${S3_ACCESS_KEY:?S3_ACCESS_KEY is required}"
  : "${S3_SECRET_KEY:?S3_SECRET_KEY is required}"
fi

# Directory on the *host* where cluster-backup.sh writes backups
HOST_BACKUP_DIR="${HOST_BACKUP_DIR:-/home/core/etcd_backups}"

# S3 object key prefix, usually set per-cluster
S3_PREFIX="${S3_PREFIX:-etcd-backup}"

# MinIO client alias name
MC_ALIAS_NAME="${MC_ALIAS_NAME:-backup}"

log() {
  echo "[etcd-backup] $*"
}

############################################
# Start
############################################

log "Starting etcd backup at $(date -Is)"
log "Host backup dir: ${HOST_BACKUP_DIR}"
log "S3 endpoint: ${S3_ENDPOINT:-<skip>}"
log "S3 bucket: ${S3_BUCKET:-<skip>}"
log "S3 prefix: ${S3_PREFIX}"
log "SKIP_S3_UPLOAD=${SKIP_S3_UPLOAD}"

# If a custom CA is mounted into anchors (for internal S3),
# update the trust store. For AWS public S3 this is harmless.
if [[ -d /etc/pki/ca-trust/source/anchors ]]; then
  log "Updating CA trust store from /etc/pki/ca-trust/source/anchors"
  if ! update-ca-trust; then
    log "WARNING: update-ca-trust failed; TLS may not trust custom CA"
  fi
fi

# Ensure the host backup directory exists
mkdir -p "/host${HOST_BACKUP_DIR}"

############################################
# Run cluster-backup.sh on the *host*
############################################

log "Running cluster-backup.sh on host via chroot..."
chroot /host /bin/bash -c "
  set -Eeuo pipefail
  mkdir -p '${HOST_BACKUP_DIR}'
  /usr/local/bin/cluster-backup.sh '${HOST_BACKUP_DIR}'
"

############################################
# Locate the latest snapshot + static resources
############################################

SNAPSHOT_PATH=$(ls -1t "/host${HOST_BACKUP_DIR}"/snapshot_*.db 2>/dev/null | head -n1 || true)
STATIC_PATH=$(ls -1t "/host${HOST_BACKUP_DIR}"/static_kuberesources_*.tar.gz 2>/dev/null | head -n1 || true)

if [[ -z "${SNAPSHOT_PATH}" || -z "${STATIC_PATH}" ]]; then
  log "ERROR: Snapshot or static_kuberesources file not found under /host${HOST_BACKUP_DIR}"
  exit 1
fi

log "Found snapshot: ${SNAPSHOT_PATH}"
log "Found static resources: ${STATIC_PATH}"

TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
SNAPSHOT_OBJ="${S3_PREFIX}/snapshot_${TS}.db"
STATIC_OBJ="${S3_PREFIX}/static_kuberesources_${TS}.tar.gz"

############################################
# Test mode: skip S3 upload
############################################

if [[ "${SKIP_S3_UPLOAD}" == "true" ]]; then
  log "SKIP_S3_UPLOAD=true; not contacting S3."
  log "Snapshot left on host: ${SNAPSHOT_PATH}"
  log "Static resources left on host: ${STATIC_PATH}"
  log "Backup (host-only) completed at $(date -Is)"
  exit 0
fi

############################################
# Configure mc and upload to S3
############################################

log "Configuring MinIO alias '${MC_ALIAS_NAME}' with CA-validated TLS"
/usr/local/bin/mc alias set "${MC_ALIAS_NAME}" "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}"

# We assume the bucket already exists (created in AWS or internal S3).
# IAM policy does NOT need s3:CreateBucket; we don't call mc mb.

log "Uploading snapshot and static_kuberesources to S3..."
/usr/local/bin/mc cp "${SNAPSHOT_PATH}" "${MC_ALIAS_NAME}/${S3_BUCKET}/${SNAPSHOT_OBJ}"
/usr/local/bin/mc cp "${STATIC_PATH}"   "${MC_ALIAS_NAME}/${S3_BUCKET}/${STATIC_OBJ}"

############################################
# Cleanup on host
############################################

log "Cleaning up host backup files..."
rm -f "/host${HOST_BACKUP_DIR}"/snapshot_*.db "/host${HOST_BACKUP_DIR}"/static_kuberesources_*.tar.gz

log "Backup completed successfully at $(date -Is)"
