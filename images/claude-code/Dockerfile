# syntax=docker/dockerfile:1
#
# Claude Code (native binary), packaged as an NVIDIA OpenShell sandbox image.
#
#   podman build -t localhost/claude-code:2.1.318 images/claude-code   (from the repo root)
#   openshell sandbox create --from ghcr.io/stephenl03/claude-code:2.1.318 --provider claude-code -- claude
#
# No credentials are baked in. Auth comes from ANTHROPIC_API_KEY or
# CLAUDE_CODE_OAUTH_TOKEN supplied at runtime by an OpenShell provider (README.md).
#
# Same conventions as images/pi: OpenShell custom-image contract (non-root USER,
# workspace = HOME = /sandbox, UID/GID 10001, CMD replaced by the supervisor).

# Ubuntu 24.04 (OpenShell's default sandbox base), pinned to the OCI index digest.
ARG BASE_IMAGE=nvcr.io/nvidia/base/ubuntu:24.04@sha256:d9461f428eea54e553add3a5158a0f245c6e1ea73efc59fff8e98e3d4a38e378

# ---------------------------------------------------------------------------
# fetch: download the pinned Claude Code release and verify it.
#   1. Anthropic release-signing key, fingerprint checked against the value
#      published in the Claude Code setup docs.
#   2. manifest.json + detached signature for the version, gpg --verify.
#   3. manifest checksum for linux-x64 must equal the pinned CLAUDE_CODE_SHA256.
#   4. the downloaded binary must match that checksum.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS fetch

ARG CLAUDE_CODE_VERSION=2.1.318
ARG CLAUDE_CODE_SHA256=708c77b204db30086ff6f1ed34577bda03e1be74ced80557cbf7b54249ebf0bd
ARG CLAUDE_SIGNING_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
ARG RELEASES=https://downloads.claude.ai/claude-code-releases

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg jq \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    export GNUPGHOME="$(mktemp -d)"; \
    cd /tmp; \
    curl -fsSLo claude-code.asc https://downloads.claude.ai/keys/claude-code.asc; \
    gpg --batch --import claude-code.asc; \
    gpg --batch --with-colons --fingerprint | grep -q "^fpr:::::::::${CLAUDE_SIGNING_KEY_FPR}:"; \
    curl -fsSLo manifest.json     "${RELEASES}/${CLAUDE_CODE_VERSION}/manifest.json"; \
    curl -fsSLo manifest.json.sig "${RELEASES}/${CLAUDE_CODE_VERSION}/manifest.json.sig"; \
    gpg --batch --status-fd 1 --verify manifest.json.sig manifest.json \
      | grep -Eq "^\[GNUPG:\] VALIDSIG .*${CLAUDE_SIGNING_KEY_FPR}( |\$)"; \
    test "$(jq -r '.version' manifest.json)" = "${CLAUDE_CODE_VERSION}"; \
    test "$(jq -r '.platforms["linux-x64"].checksum' manifest.json)" = "${CLAUDE_CODE_SHA256}"; \
    curl -fsSLo claude "${RELEASES}/${CLAUDE_CODE_VERSION}/linux-x64/claude"; \
    echo "${CLAUDE_CODE_SHA256}  claude" | sha256sum -c -; \
    install -m 0755 claude /claude; \
    rm -rf "${GNUPGHOME}" /tmp/claude /tmp/manifest.json* /tmp/claude-code.asc

# ---------------------------------------------------------------------------
# final image
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}

ARG CLAUDE_CODE_VERSION=2.1.318
ARG GH_VERSION=2.103.3
ARG SANDBOX_UID=10001
ARG SANDBOX_GID=10001

ENV DEBIAN_FRONTEND=noninteractive

# Base tools. iproute2/procps/openssh-sftp-server mirror the OpenShell community
# base image (supervisor networking diagnostics + `openshell sandbox upload/download`).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq ripgrep fd-find less openssh-client \
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

# Claude Code: a single self-contained binary (no Node.js needed). Installed at
# /usr/local/bin/claude, the path NVIDIA's claude-code provider profile and the
# community base policy expect. Root-owned and outside /sandbox, so it is
# read-only to the agent and every image upgrade replaces it.
COPY --from=fetch /claude /usr/local/bin/claude

# Runtime user matching OpenShell's Kubernetes default identity. HOME = /sandbox
# (the only writable tree besides /tmp under the OpenShell filesystem policy).
RUN groupadd --gid "${SANDBOX_GID}" sandbox \
 && useradd --uid "${SANDBOX_UID}" --gid sandbox --home-dir /sandbox --no-create-home \
      --shell /bin/bash sandbox \
 && install -d -o sandbox -g sandbox -m 0775 /sandbox

COPY config/gitconfig /etc/gitconfig
COPY config/policy.yaml /etc/openshell/policy.yaml

# No self-updates (the image is the update channel), no telemetry / error
# reporting / other nonessential traffic. Names per code.claude.com/docs/en/env-vars.
# DISABLE_INSTALLATION_CHECKS: the binary is deliberately not in ~/.local/bin.
ENV HOME=/sandbox \
    DISABLE_AUTOUPDATER=1 \
    DISABLE_UPDATES=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1 \
    DISABLE_INSTALLATION_CHECKS=1 \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

USER sandbox:sandbox
WORKDIR /sandbox

RUN claude --version \
 && rm -rf /sandbox/.claude /sandbox/.claude.json /sandbox/.cache \
 && printf 'export PATH="/usr/local/bin:/usr/bin:/bin"\nexport PS1="\\u@\\h:\\w\\$ "\n' > /sandbox/.bashrc \
 && printf '[ -f ~/.bashrc ] && . ~/.bashrc\n' > /sandbox/.profile \
 && chmod -R g+rwX /sandbox

LABEL org.opencontainers.image.title="claude-code" \
      org.opencontainers.image.description="Claude Code ${CLAUDE_CODE_VERSION} (native binary) for NVIDIA OpenShell" \
      org.opencontainers.image.source="https://github.com/stephenl03/openshell-containers" \
      org.opencontainers.image.url="https://github.com/stephenl03/openshell-containers/tree/main/images/claude-code" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${CLAUDE_CODE_VERSION}"

# OpenShell replaces this with its supervisor; pass `-- claude` at sandbox create.
CMD ["/bin/bash"]
