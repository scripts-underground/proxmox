# scripts-underground-proxmox

Proxmox scripts — upstream picks, community additions, fork-friendly.

## Development

The recommended way to work on this project is inside the included devcontainer.
It ships with everything the project needs — Ruby 3.3, Jekyll and plugins,
Go 1.25 for the AST tool, `pre-commit`, `shellcheck`, and `shfmt` — and wires
the pre-commit git hook automatically on container create. Jekyll auto-starts
on port 4000 (forwarded to the host).

### Open in a devcontainer

- **VS Code** — open the project folder, then run "Reopen in Container"
  (requires the Dev Containers extension)
- **GitHub Codespaces** — open the repo on GitHub, click the green "Code"
  button, "Codespaces" tab, then "Create codespace on main"
- **DevPod** — [DevPod](https://devpod.sh/) works too; the helper script
  `.devcontainer/devpod_reset.sh` is included to nuke stale containers when
  you need a fresh build

Once inside the devcontainer, no further setup is required — commits will
run the pre-commit hooks automatically and Jekyll will be reachable at
`http://localhost:4000`.

### Without a devcontainer

If you can't or prefer not to use a devcontainer, you can set up the toolchain
on your host directly.

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

#### Pre-commit hooks (host setup)

Inside the devcontainer these are wired automatically. On the host, install
manually before your first commit:

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
