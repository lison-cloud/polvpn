# polvpn toolbox: OpenTofu + Ansible + Google Cloud CLI + OpenSSH.
#
# Built automatically by ../polvpn. The image is tagged with a hash of this
# file plus the host uid/gid, so editing this file triggers a rebuild.
#
# The container runs as the host uid:gid so files written to the mounted
# project are owned by the operator, not root. OpenSSH refuses to start when
# the current uid has no passwd entry ("No user exists for uid ..."), so a
# matching user is created at build time from the PUID/PGID build args.

FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

ARG TOFU_VERSION=1.13.9
# SHA256 of tofu_<version>_linux_<arch>.tar.gz; must also match the release's
# signed SHA256SUMS.
ARG TOFU_SHA256_AMD64=b34b327cc1ef07178207b6f2cd1f5276537d3e5b7be316500f6dac50d4c0a857
ARG TOFU_SHA256_ARM64=5dc196dde75b667e4806d358310ec96742774cd0993c54c1237efee5644b69b8
# OpenTofu release signing key (https://get.opentofu.org/opentofu.asc).
ARG TOFU_GPG_FINGERPRINT=E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80
ARG ANSIBLE_CORE_VERSION=2.22.0
ARG GCLOUD_VERSION=594.0.0-0
ARG PUID=1000
ARG PGID=1000
# Set by BuildKit to the build platform's architecture; no default here, a
# default would override BuildKit's value (arm64 hosts would get amd64 OpenTofu).
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Base packages. qrencode/wireguard-tools are handy for generating client
# configs and QR codes on the controller side.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl bash less \
      openssh-client python3 python3-venv \
      qrencode wireguard-tools \
 && rm -rf /var/lib/apt/lists/*

# OpenTofu from the official GitHub release archive. SHA256SUMS must carry a
# valid signature by the pinned OpenTofu key, and the archive must match both
# SHA256SUMS and the checksum pinned above. gpg is only needed for this step.
RUN set -eu; \
    case "${TARGETARCH:-}" in \
      amd64) sum="${TOFU_SHA256_AMD64}" ;; \
      arm64) sum="${TOFU_SHA256_ARM64}" ;; \
      "") echo "TARGETARCH is empty: build with BuildKit (docker buildx), which sets it" >&2; exit 1 ;; \
      *) echo "unsupported architecture '${TARGETARCH}' (only amd64 and arm64)" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends gpg gpgv; \
    tmp="$(mktemp -d)"; cd "${tmp}"; \
    url="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}"; \
    tgz="tofu_${TOFU_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    sums="tofu_${TOFU_VERSION}_SHA256SUMS"; \
    curl -fsSLO "${url}/${tgz}"; \
    curl -fsSLO "${url}/${sums}"; \
    curl -fsSLO "${url}/${sums}.gpgsig"; \
    curl -fsSLo opentofu.asc https://get.opentofu.org/opentofu.asc; \
    gpg --dearmor <opentofu.asc >opentofu.gpg; \
    gpgv --status-fd 1 --keyring ./opentofu.gpg "${sums}.gpgsig" "${sums}" >gpgv.status; \
    grep -Eq "^\[GNUPG:\] VALIDSIG .* ${TOFU_GPG_FINGERPRINT}\$" gpgv.status \
      || { echo "SHA256SUMS is not signed by ${TOFU_GPG_FINGERPRINT}" >&2; exit 1; }; \
    grep -E "^${sum}  ${tgz}\$" "${sums}" \
      || { echo "pinned checksum for ${tgz} not in signed ${sums}" >&2; exit 1; }; \
    echo "${sum}  ${tgz}" | sha256sum -c -; \
    tar -xzf "${tgz}" --no-same-owner -C /usr/local/bin tofu; \
    cd /; rm -rf "${tmp}" /root/.gnupg; \
    apt-get purge -y --auto-remove gpg; \
    rm -rf /var/lib/apt/lists/*; \
    tofu version

# Google Cloud CLI from the official apt repository (pinned). The bundled
# Python interpreter is dropped; gcloud uses the system python3 instead.
RUN set -eu; \
    curl -fsSLo /usr/share/keyrings/cloud.google.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends "google-cloud-cli=${GCLOUD_VERSION}"; \
    rm -rf /var/lib/apt/lists/* /usr/lib/google-cloud-sdk/platform/bundledpythonunix; \
    find /usr/lib/google-cloud-sdk -name '__pycache__' -type d -prune -exec rm -rf {} +
ENV CLOUDSDK_PYTHON=/usr/bin/python3

# ansible-core in a venv (Debian's python is PEP 668 "externally managed").
RUN python3 -m venv /opt/ansible \
 && /opt/ansible/bin/pip install "ansible-core==${ANSIBLE_CORE_VERSION}" netaddr jmespath \
 && find /opt/ansible -name '__pycache__' -type d -prune -exec rm -rf {} +
ENV PATH=/opt/ansible/bin:$PATH

# User matching the host uid/gid (see header). uid 0 needs nothing.
RUN set -eu; \
    if [ "${PUID}" != 0 ]; then \
      getent group "${PGID}" >/dev/null || groupadd -g "${PGID}" polvpn; \
      useradd -o -u "${PUID}" -g "${PGID}" -M -d /home/polvpn -s /bin/bash polvpn; \
    fi; \
    mkdir -p /home/polvpn; \
    chown "${PUID}:${PGID}" /home/polvpn; \
    chmod 0755 /home/polvpn

ENV HOME=/home/polvpn \
    CLOUDSDK_CONFIG=/work/.secrets/gcloud \
    CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK=1

USER ${PUID}:${PGID}
WORKDIR /work
CMD ["bash"]
