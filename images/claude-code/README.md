# claude-code

[Claude Code](https://code.claude.com/docs) 2.1.318 (native binary) packaged as an NVIDIA
OpenShell sandbox image for the k3s (amd64) cluster. The image holds no credentials.

Image: `ghcr.io/stephenl03/claude-code` (tags `2.1.318`, `sha-<short>`, `latest`), built and
pushed by [`.github/workflows/build.yml`](../../.github/workflows/build.yml). The version tag
comes from [`VERSION`](VERSION).

| Component | Version / pin |
|---|---|
| Base | `nvcr.io/nvidia/base/ubuntu:24.04@sha256:d9461f42…e378` (same as `pi`) |
| Claude Code | 2.1.318 native linux-x64 binary at `/usr/local/bin/claude` (see below) |
| gh | 2.103.3 (official cli.github.com apt repo) |
| Other tools | git, curl, jq, ripgrep, fd (`fd-find`, symlinked), less, openssh-client, iproute2, procps, openssh-sftp-server |
| Node.js | not installed: the native binary does not need it |
| User | `sandbox`, UID/GID 10001, HOME=`/sandbox` |

## How Claude Code is installed

The npm package (`@anthropic-ai/claude-code`) is now only a wrapper: its `postinstall` copies a
platform binary out of an optional dependency. With `--ignore-scripts`, `claude` is left as a stub
that prints "claude native binary not installed" and exits 1. So this image does **not** use npm.

Instead, a separate `fetch` build stage does what the
[binary integrity docs](https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing)
describe:

1. Download Anthropic's release signing key and require fingerprint
   `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`.
2. Download `manifest.json` and `manifest.json.sig` for the pinned version and `gpg --verify` them.
3. Require that the manifest's `linux-x64` checksum equals the pinned `CLAUDE_CODE_SHA256`.
4. Download `…/claude-code-releases/<version>/linux-x64/claude` and `sha256sum -c` it.

Only the verified binary is copied into the final image. `claude install` is not run, so there is
no `~/.local/bin` launcher and no auto-update machinery.

To bump the version: set `CLAUDE_CODE_VERSION` (both stages) and `CLAUDE_CODE_SHA256` in the
Dockerfile, and `VERSION`. Get the checksum from
`https://downloads.claude.ai/claude-code-releases/<version>/manifest.json`
(`.platforms["linux-x64"].checksum`). The build fails if it doesn't match the signed manifest.

## Environment baked into the image

| Variable | Effect |
|---|---|
| `DISABLE_AUTOUPDATER=1` | no background updates |
| `DISABLE_UPDATES=1` | also blocks `claude update` / `claude install` (the image is the update channel) |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | no telemetry, error reporting, release notes, feedback, etc. |
| `DISABLE_TELEMETRY=1`, `DISABLE_ERROR_REPORTING=1` | explicit opt-outs (also implied by the above) |
| `DISABLE_INSTALLATION_CHECKS=1` | silences the "not installed in ~/.local/bin" warning |

Names checked against <https://code.claude.com/docs/en/env-vars> on 2026-11-05.

## Auth (runtime only, via an OpenShell provider)

Claude Code reads one of:

- `ANTHROPIC_API_KEY`: a Console API key, or
- `CLAUDE_CODE_OAUTH_TOKEN`: a long-lived subscription token from `claude setup-token` (run that
  on your own machine, not in the sandbox).

With an OpenShell provider, the sandbox only sees a placeholder value. The proxy swaps in the real
credential on requests to `api.anthropic.com`.

### API key (NVIDIA's `claude-code` profile)

```bash
# once per gateway
openshell profile import \
  --url https://raw.githubusercontent.com/NVIDIA/OpenShell/main/providers/claude-code.yaml --global

# reads ANTHROPIC_API_KEY from your shell
openshell provider create --name claude --type claude-code --from-existing
# or: openshell provider create --name claude --type claude-code --credential ANTHROPIC_API_KEY

openshell sandbox create --name claude \
  --from ghcr.io/stephenl03/claude-code:2.1.318 \
  --provider claude -- claude
```

NVIDIA's profile lists `/usr/bin/claude` and `/usr/local/bin/claude` as binaries; this image uses
the latter, so the profile works unchanged. It also allows `statsig.anthropic.com` and `sentry.io`,
which this image should never contact.

### Subscription token (`claude setup-token`)

NVIDIA's profile only knows the API-key header (`x-api-key`). For an OAuth token, which is sent as
`Authorization: Bearer`, import the profile in this directory:

```bash
openshell profile lint   -f images/claude-code/providers/claude-code-oauth.yaml
openshell profile import -f images/claude-code/providers/claude-code-oauth.yaml --global

export CLAUDE_CODE_OAUTH_TOKEN=...   # from `claude setup-token`
openshell provider create --name claude-sub --type claude-code-oauth --credential CLAUDE_CODE_OAUTH_TOKEN

openshell sandbox create --name claude \
  --from ghcr.io/stephenl03/claude-code:2.1.318 \
  --provider claude-sub -- claude
```

### GitHub

`/etc/gitconfig` uses `!/usr/bin/gh auth git-credential` for github.com and gist.github.com. Attach
a GitHub provider (`openshell profile import --url …/providers/github.yaml --global`, then
`openshell provider create --name gh --type github --from-existing`) or run `gh auth login` inside
the sandbox.

## Policy

`/etc/openshell/policy.yaml` is modelled on the `claude_code` and GitHub blocks of the
community base sandbox policy (`NVIDIA/OpenShell-Community` `sandboxes/base/policy.yaml` @
`edb65583`). It allows `api.anthropic.com` (TLS terminated, so credentials can be injected),
`platform.claude.com` and `claude.ai` for `/usr/local/bin/claude`, read-only git to github.com,
and read-only api.github.com for gh and claude. Override with `--policy`.

## Notes and caveats

- **Untested on the cluster.** The image builds and passes the smoke test (`claude --version` as
  UID 10001, no credential files). The policy, both provider flows and a real `claude -p` call
  through the OpenShell proxy have not been tried against the 0.1.7 gateway yet.
- On first interactive start Claude Code may ask to confirm the theme / API key. Its state goes to
  `/sandbox/.claude*`, which persists on the sandbox PVC.
- `/sandbox` is seeded from the image only once per sandbox (see the `pi` README). `claude` itself
  lives in `/usr/local/bin`, so a new image tag updates it on the next sandbox.
- Licensing: the repository's MIT license covers the build files only. Claude Code itself is
  Anthropic's proprietary software, used under Anthropic's terms.
