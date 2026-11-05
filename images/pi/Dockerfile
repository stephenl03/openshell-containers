# syntax=docker/dockerfile:1
#
# pi coding agent + pi-claude-auth, packaged as an NVIDIA OpenShell sandbox image.
#
#   podman build -t localhost/pi:1.5.0 images/pi      (from the repo root)
#   openshell sandbox create --from ghcr.io/stephenl03/pi:1.5.0 -- pi
#
# No credentials are baked in. See README.md for how auth is supplied at runtime.
#
# OpenShell custom-image contract (NVIDIA/OpenShell examples/bring-your-own-container,
# OpenShell-Community sandboxes/base):
#   - standard Linux base, non-root OCI USER, workspace = /sandbox
#   - CMD/ENTRYPOINT is replaced by the supervisor; pass the command after `--`
#   - on Kubernetes the agent runs as UID/GID 10001 (driver default) and /sandbox
#     is a PVC seeded ONCE from this image's /sandbox (later image upgrades do not
#     propagate into an existing sandbox's /sandbox).

# Ubuntu 24.04 (OpenShell's default sandbox base), pinned to the OCI index digest.
ARG BASE_IMAGE=nvcr.io/nvidia/base/ubuntu:24.04@sha256:d9461f428eea54e553add3a5158a0f245c6e1ea73efc59fff8e98e3d4a38e378
FROM ${BASE_IMAGE}

# Node 24 LTS (pi 1.5.0 requires >= 22.19.0). sha256 from nodejs.org SHASUMS256.txt.
ARG NODE_VERSION=24.22.2
ARG NODE_SHA256=48cc0e21e048790e54c0cf5749c2725005313d652651c40b7a21feb9697aaf75
ARG GH_VERSION=2.103.3
ARG PI_VERSION=1.5.0
ARG PI_CLAUDE_AUTH_VERSION=0.1.3
ARG SANDBOX_UID=10001
ARG SANDBOX_GID=10001

ENV DEBIAN_FRONTEND=noninteractive

# Base tools. iproute2/procps/openssh-sftp-server mirror the OpenShell community
# base image (supervisor networking diagnostics + `openshell sandbox upload/download`).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq ripgrep fd-find xz-utils less openssh-client \
      iproute2 procps openssh-sftp-server \
 && ln -s /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI from the official apt repo, pinned version.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod 644 /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh=${GH_VERSION} \
 && rm -rf /var/lib/apt/lists/*

# Node.js from the official tarball, checksum-verified.
RUN set -eux; \
    tarball="node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    curl -fsSLo "/tmp/${tarball}" "https://nodejs.org/dist/v${NODE_VERSION}/${tarball}"; \
    echo "${NODE_SHA256}  /tmp/${tarball}" | sha256sum -c -; \
    tar -xJf "/tmp/${tarball}" -C /usr/local --strip-components=1 --no-same-owner \
        --exclude='*/share/doc' --exclude='*/share/man' --exclude='*/include' \
        --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE'; \
    rm -f "/tmp/${tarball}"; \
    node --version; npm --version

# pi, exact version. --ignore-scripts as in pi's own containerization docs.
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" \
 && npm cache clean --force \
 && pi --version

# Runtime user matching OpenShell's Kubernetes default identity. HOME = /sandbox
# (the only writable tree besides /tmp under the OpenShell filesystem policy).
RUN groupadd --gid "${SANDBOX_GID}" sandbox \
 && useradd --uid "${SANDBOX_UID}" --gid sandbox --home-dir /sandbox --no-create-home \
      --shell /bin/bash sandbox \
 && install -d -o sandbox -g sandbox -m 0775 /sandbox

COPY config/gitconfig /etc/gitconfig
COPY config/policy.yaml /etc/openshell/policy.yaml

ENV HOME=/sandbox \
    PI_TELEMETRY=0 \
    PI_SKIP_VERSION_CHECK=1 \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

USER sandbox:sandbox
WORKDIR /sandbox

# pi config (settings + theme reused from Marvino-Fransisco/pi-coding-agent-configs
# @ ce045706c81470789aff5a28e3cf168d8abb7093, adapted), then pi-claude-auth
# installed through pi's own package manager at an exact version.
COPY --chown=sandbox:sandbox config/settings.json /sandbox/.pi/agent/settings.json
COPY --chown=sandbox:sandbox config/themes/ /sandbox/.pi/agent/themes/
RUN pi install "npm:pi-claude-auth@${PI_CLAUDE_AUTH_VERSION}" \
 && npm cache clean --force \
 && rm -rf /sandbox/.npm /sandbox/.pi/agent/tmp \
 && test ! -e /sandbox/.pi/agent/auth.json \
 && test ! -e /sandbox/.claude \
 && printf 'export PATH="/usr/local/bin:/usr/bin:/bin"\nexport PS1="\\u@\\h:\\w\\$ "\n' > /sandbox/.bashrc \
 && printf '[ -f ~/.bashrc ] && . ~/.bashrc\n' > /sandbox/.profile \
 && chmod -R g+rwX /sandbox

LABEL org.opencontainers.image.title="pi" \
      org.opencontainers.image.description="pi coding agent ${PI_VERSION} + pi-claude-auth ${PI_CLAUDE_AUTH_VERSION} for NVIDIA OpenShell" \
      org.opencontainers.image.source="https://github.com/stephenl03/openshell-containers" \
      org.opencontainers.image.url="https://github.com/stephenl03/openshell-containers/tree/main/images/pi" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${PI_VERSION}" \
      io.pi.version="${PI_VERSION}" \
      io.pi.claude-auth.version="${PI_CLAUDE_AUTH_VERSION}"

# OpenShell replaces this with its supervisor; pass `-- pi` at sandbox create.
CMD ["/bin/bash"]
