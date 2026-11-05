# pi

The [pi coding agent](https://pi.dev) (`@earendil-works/pi-coding-agent` 1.5.0) plus the
[`pi-claude-auth`](https://www.npmjs.com/package/pi-claude-auth) 0.1.3 extension, packaged as an
NVIDIA OpenShell sandbox image for the k3s (amd64) cluster. The image holds no credentials.

Image: `ghcr.io/stephenl03/pi` (tags `1.5.0`, `sha-<short>`, `latest`), built and pushed by
[`.github/workflows/build.yml`](../../.github/workflows/build.yml). The version tag comes from
[`VERSION`](VERSION); bump it together with `PI_VERSION` in the Dockerfile.

| Component | Version / pin |
|---|---|
| Base | `nvcr.io/nvidia/base/ubuntu:24.04@sha256:d9461f42…e378` (OCI index) |
| Node.js | 24.22.2 LTS, official tarball, sha256-checked |
| pi | `@earendil-works/pi-coding-agent@1.5.0` (`npm -g --ignore-scripts`) |
| pi-claude-auth | `npm:pi-claude-auth@0.1.3`, installed with `pi install` at build time |
| gh | 2.103.3 (official cli.github.com apt repo) |
| Other tools | git, curl, jq, ripgrep, fd (`fd-find`, symlinked), less, openssh-client, iproute2, procps, openssh-sftp-server |
| User | `sandbox`, UID/GID 10001, HOME=`/sandbox` |

## Build locally (rootless podman)

```bash
# from the repo root
podman build --platform linux/amd64 -t localhost/pi:1.5.0 images/pi
podman run --rm --user 10001:10001 localhost/pi:1.5.0 pi --version
```

CI builds the same Dockerfile for linux/amd64 only (the Node tarball is the x64 build).

## Layout and OpenShell notes

- `/sandbox` is HOME and the workspace. Under the OpenShell policy, only `/sandbox` and `/tmp` are
  writable, so all pi state lives under `/sandbox/.pi/agent`.
- **On Kubernetes, `/sandbox` is a PVC that is filled from the image only the first time a sandbox
  starts** (OpenShell v0.1.7 `workspace-init`, sentinel file `.workspace-initialized`). If you rebuild
  the image, existing sandboxes keep their old `/sandbox/.pi/agent` (settings and pi-claude-auth).
  To pick up a new image, create a new sandbox. Everything outside `/sandbox` comes from the image
  on every start: pi, node, gh, `/etc/gitconfig`, and `/etc/openshell/policy.yaml`.
- `/etc/gitconfig` sets `!/usr/bin/gh auth git-credential` as the credential helper for github.com
  and gist.github.com.
- `/etc/openshell/policy.yaml` is a trimmed copy of the community `pi` sandbox policy. It allows
  api.anthropic.com, claude.ai and platform.claude.com for pi/node, read-only git for github.com,
  and read-only access to api.github.com for gh. **It has not been tested against gateway 0.1.7.**
  You can override it with `--policy`.
- The image sets `PI_TELEMETRY=0` and `PI_SKIP_VERSION_CHECK=1`, and turns off
  `enableInstallTelemetry` and `enableAnalytics` in `settings.json`.

## Run in OpenShell

```bash
openshell sandbox create --name pi --from ghcr.io/stephenl03/pi:1.5.0 -- pi
# or keep it running and attach later:
openshell sandbox create --name pi --from ghcr.io/stephenl03/pi:1.5.0 --detach -- sleep infinity
openshell sandbox exec -n pi -- pi
```

OpenShell replaces the image's CMD with its supervisor, so always pass the command after `--`.

## Credentials (supplied at runtime, never baked in)

### pi-claude-auth (Claude Pro/Max subscription)

On Linux, the extension reads one file: `$HOME/.claude/.credentials.json`, which in this image is
**`/sandbox/.claude/.credentials.json`**. It does not read any environment variable for the
credential. The file has the same format as Claude Code's own credentials file:

```json
{"claudeAiOauth": {"accessToken": "...", "refreshToken": "...", "expiresAt": 1767225600000, "subscriptionType": "max"}}
```

`accessToken` and `refreshToken` must be strings, and `expiresAt` must be epoch milliseconds,
otherwise the file is ignored. When pi starts, the extension:

- copies the token into `/sandbox/.pi/agent/auth.json` (mode 0600, key `anthropic`, `type: oauth`)
- re-syncs `auth.json` every 5 minutes
- when the token is within 60 s of expiry, POSTs the refresh token to
  `https://claude.ai/v1/oauth/token` (Claude Code's client_id) and writes the new tokens back into
  `.credentials.json`. If that fails, it falls back to running `claude -p . --model haiku`. The
  `claude` CLI is not in this image, so that fallback just fails.

The file has to be writable by UID 10001 so refreshed tokens can be saved. One way to deliver it
(not yet tested on the cluster):

```bash
openshell sandbox upload pi ./claude-creds-dir /sandbox/.claude   # dir containing .credentials.json
openshell sandbox exec -n pi -- chmod 600 /sandbox/.claude/.credentials.json
```

Caveats:

- **Refresh-token rotation.** If the sandbox and your Mac share one Claude login, a refresh in one
  place invalidates the refresh token in the other. A separate login, or a long-lived token from
  `claude setup-token`, avoids this.
- **Terms of service.** The extension sets a Claude Code user-agent, adds Claude Code's
  `x-anthropic-billing-header`, and moves pi's system prompt into the first user message to get
  past Anthropic's check on system prompts in subscription requests. Using a subscription this
  way, in a third-party harness that impersonates Claude Code, may break Anthropic's consumer
  terms. You decide whether to accept that risk.
- **Known drift with pi 1.5.0.** The extension's in-memory credential injection fails
  (`credential_apply_error: Cannot read properties of undefined (reading 'set')`, because
  `ctx.modelRegistry.authStorage` is gone). The `auth.json` seeding and `getApiKey` hook still
  work: in tests, pi used the seeded token. If `ANTHROPIC_API_KEY` is also set, it may take
  precedence.

### Alternatives that don't need the extension

- Built into pi: `ANTHROPIC_OAUTH_TOKEN` (for example from `claude setup-token`) or
  `ANTHROPIC_API_KEY` as environment variables. These could come from an OpenShell provider so
  that the sandbox only sees a placeholder and the proxy injects the real value. This is how the
  studio-llama provider works. Not yet tested with pi.
- GitHub: run `gh auth login` inside the sandbox, or pass `GH_TOKEN` through an OpenShell provider.

## Provenance

- Config ideas taken from `Marvino-Fransisco/pi-coding-agent-configs` @
  `ce045706c81470789aff5a28e3cf168d8abb7093`: `settings.json` (adapted) and `themes/marvino.json`.
  The repo's theme file had `"name": "white-border"` while its settings referred to `marvino`;
  the name is fixed in this copy.
- Not reused:
  - The repo's committed `pi/agent/auth.json`, which contains real Anthropic OAuth tokens: a leaked
    secret upstream.
  - Its `Dockerfile` (node:bookworm base, unpinned pi, `yq` from `releases/latest`).
  - docker-compose (mounts SSH keys and a credentials file).
  - `run.sh` and `entrypoint.sh`.
  - The ZAI model defaults.
  - The extensions: `permission-gate.ts` checks `event.tool`, but pi 1.5 uses `event.toolName`,
    so the gate never fires. The others only change how the TUI looks.
- The installed pi-claude-auth files are byte-identical to the reviewed tarball (39 files,
  sha512 `XhSYCoV4…tvxA==`).
