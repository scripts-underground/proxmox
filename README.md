# scripts-underground-proxmox

Proxmox scripts — upstream picks, community additions, fork-friendly.

## Local Development

### Prerequisites

- Ruby 3.x
- Bundler

### Setup

```bash
bundle install
```

### Build & Serve

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

### Docker (no Ruby install)

```bash
docker run --rm -it \
  -v "$PWD:/srv/jekyll" \
  -p 4000:4000 \
  jekyll/jekyll:latest \
  jekyll serve --livereload
```

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
