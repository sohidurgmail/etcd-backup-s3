# OpenShift etcd Backup to S3 (CronJob + GitOps)

This repository provides a small, production-oriented setup for backing up **OpenShift etcd** from control-plane nodes and uploading the backups to an **S3-compatible object store** (AWS S3 or internal S3) using a Kubernetes CronJob.

It is designed to be GitOps-friendly (Kustomize), disconnected-ready, and to avoid putting any credentials into Git.

---

## 1. What this does

- Runs the **official OpenShift `cluster-backup.sh`** script on a control-plane node:
  - Creates an etcd snapshot (`snapshot_*.db`)
  - Creates a Kubernetes static resources archive (`static_kuberesources_*.tar.gz`)
- Uploads both artifacts to an **S3 bucket** via the MinIO client (`mc`).
- Cleans up backup files from the node after a successful upload.
- Runs on a schedule (default: **daily at midnight**).
- Ships as a small UBI-based container image you can host on Quay or any OCI registry.

This is **not** an official Red Hat project; it is a small helper around `cluster-backup.sh` that automates S3 uploads.

---

## 2. Repository layout

Suggested structure (adjust if your repo differs):

```text
.
├── Dockerfile
├── backup-to-s3.sh
├── kustomization.yaml
├── namespace.yaml
├── serviceaccount.yaml
├── rbac-privileged-scc.yaml
├── configmap-etcd-backup-config.yaml
├── cronjob-etcd-backup.yaml
├── prometheusrule-etcd-backup.yaml      # optional alerting
└── README.md
