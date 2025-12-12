# Build this on a connected build host, then push to your internal registry.
FROM registry.redhat.io/ubi9/ubi-minimal:latest

# Install only what we need (ubi-minimal already has coreutils-single and curl-minimal)
RUN microdnf install -y \
      bash \
      findutils \
      tar \
      gzip \
      ca-certificates \
    && microdnf clean all

# Install MinIO client (mc) - use the official Linux amd64 URL
RUN curl -L "https://dl.min.io/client/mc/release/linux-amd64/mc" \
      -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc

# Copy backup script into image
COPY backup-to-s3.sh /usr/local/bin/backup-to-s3.sh
RUN chmod +x /usr/local/bin/backup-to-s3.sh

ENTRYPOINT ["/usr/local/bin/backup-to-s3.sh"]