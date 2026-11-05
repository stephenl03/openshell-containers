# openshell-containers

Sandbox images for [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell), built by GitHub
Actions and published to GHCR. They are made for a homelab k3s cluster (amd64) running the
OpenShell gateway, but work with any OpenShell gateway that can pull from `ghcr.io`.

| Image | Contents | Pull |
|---|---|---|
| [`images/pi`](images/pi) | [pi coding agent](https://pi.dev) 1.5.0 + pi-claude-auth 0.1.3, Node 24 | `ghcr.io/stephenl03/pi:1.5.0` |
| [`images/claude-code`](images/claude-code) | [Claude Code](https://code.claude.com/docs) 2.1.318 (native binary) | `ghcr.io/stephenl03/claude-code:2.1.318` |

All images follow the same conventions:

- base `nvcr.io/nvidia/base/ubuntu:24.04`, pinned by digest
- non-root user `sandbox`, UID/GID 10001 (OpenShell's Kubernetes default), `HOME=/sandbox`
- git, gh, ripgrep, fd, jq and curl; `/etc/gitconfig` uses `gh auth git-credential` for GitHub
- a default policy at `/etc/openshell/policy.yaml`
- no credentials in the image: auth comes from OpenShell providers at runtime
- every download pinned and checksum-verified, auto-updates and telemetry off
- linux/amd64 only

## Tags

Each push to `main` that touches an image publishes `ghcr.io/stephenl03/<image>` with:

- `<version>` from `images/<image>/VERSION` (for example `pi:1.5.0`)
- `sha-<short commit>`
- `latest`

Use the version or `sha-` tag in OpenShell, not `latest`.

## CI

[`.github/workflows/build.yml`](.github/workflows/build.yml):

- **push to `main`** (paths `images/**`, `scripts/**`, the workflow): builds the images whose
  directories changed, smoke-tests them, then pushes. A change to the workflow or `scripts/`
  rebuilds every image.
- **pull_request**: build and smoke test only, nothing is pushed.
- **workflow_dispatch**: builds every image (and pushes when run on `main`).

Each image is built with `load: true`, then [`scripts/smoke-test.sh`](scripts/smoke-test.sh)
runs it as `10001:10001` without network. It checks the tool version against `VERSION`, `HOME`,
the shared tools, and that no `auth.json` / `.credentials.json` exists anywhere in the image. Only
then is it pushed (same layers, from the GHA cache). Actions are pinned to commit SHAs.

## Add an image

1. Create `images/<name>/` with:
   - `Dockerfile`, following the conventions above, with OCI labels including
     `org.opencontainers.image.source="https://github.com/stephenl03/openshell-containers"` (this
     links the GHCR package to the repo)
   - `VERSION`: the tool version, one line; it becomes the image tag
   - `smoke-test.sh`: image-specific checks, appended to
     [`scripts/smoke-common.sh`](scripts/smoke-common.sh) and run inside the container. Call
     `check_version "<label>" "$(<tool> --version)"` and end with `echo "SMOKE TEST PASSED"`
   - `README.md`, plus a `config/policy.yaml` if it needs one
2. Test locally (rootless podman is fine):

   ```bash
   podman build --platform linux/amd64 -t localhost/<name>:dev images/<name>
   CONTAINER_ENGINE=podman scripts/smoke-test.sh <name> localhost/<name>:dev
   ```

3. Open a PR (CI builds and tests it), merge, and the image appears at `ghcr.io/stephenl03/<name>`.
   New GHCR packages may start out private: set them to public under
   *github.com/users/stephenl03/packages/container/&lt;name&gt;/settings → Change visibility*.

## Use with OpenShell

The cluster gateway has no Ingress. Reach it through a port-forward (kubeconfig is the auth
boundary) and register it once:

```bash
kubectl -n openshell port-forward svc/openshell 8080:8080   # keep running
openshell gateway add http://127.0.0.1:8080 --local --name k3s
openshell status
```

Then create a sandbox from an image. OpenShell replaces the image's `CMD` with its supervisor, so
put the command after `--`:

```bash
# pi
openshell sandbox create --name pi --from ghcr.io/stephenl03/pi:1.5.0 -- pi

# Claude Code with an Anthropic API key (provider profile from NVIDIA/OpenShell)
openshell profile import --global \
  --url https://raw.githubusercontent.com/NVIDIA/OpenShell/main/providers/claude-code.yaml
openshell provider create --name claude --type claude-code --from-existing
openshell sandbox create --name claude --from ghcr.io/stephenl03/claude-code:2.1.318 \
  --provider claude -- claude
```

See each image's README for auth options (subscription tokens, GitHub), policy details and
caveats. On Kubernetes, `/sandbox` is a PVC seeded from the image only when the sandbox is
first created: to pick up a new image, create a new sandbox.

## License

MIT for the build files in this repo, see [LICENSE](LICENSE). The software inside the images is
under its own licenses; Claude Code in particular is proprietary to Anthropic.
