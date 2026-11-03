# scripts-underground-proxmox

Proxmox scripts — upstream picks, community additions, fork-friendly.

## Development

The normal test route is **guest-first**: edit source in your checkout, then
deliver an exact candidate and independently owned context into the assigned VM.
Run `tests/run` inside that guest. The repository does not select or SSH to a VM.
See [tests/README.md](tests/README.md) for admission, scopes and evidence.

```bash
# Inside the assigned guest's admitted source checkout; TMPDIR is declared by context.
python3 -B tests/run --list
python3 -B tests/run --check --context "$CONTEXT" --suite workflow-ownership --mode fixture
python3 -B tests/run --run --context "$CONTEXT" --suite workflow-ownership --mode fixture
```

The trusted outer VM-owner route generates/delivers context. It binds its receipt,
actual DMI/disks/filesystems, byte+mode source manifest and selected operations
before effects. A fixture must never certify its own current values. Builds,
tests, generators and consumers execute in the assigned VM; an unavailable guest
is a blocker. Each child uses disk-backed TMPDIR.

The devcontainer provides Ruby3.3/Jekyll, Go1.25, pre-commit, ShellCheck and shfmt.
Run development containers inside the assigned VM as well.

### Open in a devcontainer

- **VS Code** — open the project folder, then run "Reopen in Container"
  (requires the Dev Containers extension)
- **GitHub Codespaces** — open the repo on GitHub, click the green "Code"
  button, "Codespaces" tab, then "Create codespace on main"
- **DevPod** — [DevPod](https://devpod.sh/) works too; the helper script
  `.devcontainer/devpod_reset.sh` is included to nuke stale containers when
  you need a fresh build

Use the assigned guest workspace when opening a development container. Its
pre-commit hooks are wired automatically. Inspect the guest's actual preview
listener and use the existing outer-owner route for any requested forwarding.

### Without a devcontainer

You can also provision the toolchain natively inside the assigned development VM.

#### Prerequisites

- Ruby 3.x
- Bundler

#### Setup

```bash
bundle install
```

#### Build & Serve

```bash
# Build once
bundle exec jekyll build

# Serve with live reload (default: http://localhost:4000)
bundle exec jekyll serve --livereload
```

The install commands on generated pages use `site.github.repository_nwo` from the
`jekyll-github-metadata` plugin. Locally without a GitHub token, it falls back
to `alexindigo/scripts-underground-proxmox` as the default repo. Pages render
fine — the base URL in install commands will just point to the fallback repo
instead of your fork.

To test with your own fork's URLs, set a GitHub token:

```bash
JEKYLL_GITHUB_TOKEN=your_token bundle exec jekyll serve
```

#### Docker (no Ruby install)

```bash
docker run --rm -it \
  -v "$PWD:/srv/jekyll" \
  -p 4000:4000 \
  jekyll/jekyll:latest \
  jekyll serve --livereload
```

#### Pre-commit hooks (guest setup)

Inside the devcontainer these are wired automatically. In a native guest checkout,
install them before your first commit:

```bash
uv tool install pre-commit    # or: pipx install pre-commit
pre-commit install            # wires .git/hooks/pre-commit
```

`shellcheck` and `shfmt` binaries also need to be on `PATH` for the hooks to
actually run those checks (e.g., `pacman -S shellcheck shfmt`, `apt install
shellcheck shfmt`).

### Project Structure

```
_ct/          CT/LXC script metadata (Jekyll collection) → /ct/:slug/
_addon/       Addon script metadata                      → /addon/:slug/
_pve/         PVE host tool metadata                     → /pve/:slug/
_vm/          VM script metadata                         → /vm/:slug/
scripts/      Executable bash scripts (one per app)
  ct/         CT/LXC install scripts
  addon/      Container addon scripts
  pve/        PVE host tool scripts
  vm/         VM creation scripts
misc/         Framework (mirrored from upstream, patched)
_layouts/     Jekyll templates
_includes/    Reusable template partials
assets/css/   Stylesheets
```
