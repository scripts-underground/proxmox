#!/usr/bin/env python3
"""
pve-scripts-migration: automated LXC script migrator.

Processes missing scripts one at a time. Each gets its own commit.
Logs results to MIGRATION-LOG.md.

Usage: python3 tools/migrate-lxc.py [--dry-run] [--start-from N]

Set REPO_BASE in env to override.
"""

import os, re, sys, subprocess, json, time, urllib.request, pathlib, textwrap

REPO = os.environ.get("REPO_BASE", "https://raw.githubusercontent.com/scripts-underground/proxmox/main")
UPSTREAM = "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
SCRIPT_DIR = pathlib.Path("scripts/lxc")
META_DIR = pathlib.Path("_lxc")
LOG_FILE = pathlib.Path("MIGRATION-LOG.md")

def sh(cmd, check=True, capture=False):
    kw = dict(shell=True, check=check)
    if capture:
        return subprocess.run(cmd, capture_output=True, text=True, **kw)
    return subprocess.run(cmd, **kw)

def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            if r.status == 200:
                return r.read().decode()
    except Exception:
        return None
    return None

def extract_var(content, name):
    m = re.search(rf'{name}="([^"]*)"', content)
    return m.group(1) if m else None

def extract_author(content):
    m = re.search(r'#\s*Author:\s*(.*)', content)
    return m.group(1).strip() if m else "tteck (tteckster)"

def extract_source(content):
    m = re.search(r'#\s*Source:\s*(.*?)(?:\s*\|\s*Github:\s*(.*))?$', content, re.MULTILINE)
    if m:
        site = m.group(1).strip()
        gh = m.group(2)
        return site, ("https://github.com/" + gh.strip() if gh else site)
    return "", ""

def extract_tags(content):
    v = extract_var(content, "var_tags")
    if v and v.startswith("${var_tags:-"):
        v = v[len("${var_tags:-"):-1]
    return [t.strip() for t in v.split(";") if t.strip()] if v else []

def extract_app(content):
    return extract_var(content, "APP") or ""

def extract_var_defaults(content):
    result = {}
    for v in ["var_cpu", "var_ram", "var_disk", "var_arm64", "var_unprivileged"]:
        result[v] = extract_var(content, v) or "2"
    return result

def extract_port(content):
    m = re.search(r'http://\$\{IP\}:(\d+)', content)
    return m.group(1) if m else None

def extract_update_function(content):
    idx = content.find("function update_script()")
    if idx == -1:
        idx = content.find("update_script()")
        if idx == -1:
            return None
    brace = content.find("{", idx)
    if brace == -1:
        return None
    depth = 1
    i = brace + 1
    while depth > 0 and i < len(content):
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
        i += 1
    return content[brace+1:i-1].strip()

def is_os_template(content, install_content):
    """Check if this is an OS template (no app install)."""
    if not install_content:
        return True
    ct_lines = content.strip().split('\n')
    # OS templates have very short ct scripts with no install logic
    if len(ct_lines) < 15:
        return True
    return False

def classify_pattern(content, install_content):
    """Classify the install pattern."""
    combined = (content or "") + (install_content or "")
    if "alpine" in content.split('\n')[0:5]:
        return "alpine"
    if "setup_uv" in combined:
        return "python-uv"
    if "setup_nodejs" in combined:
        return "nodejs"
    if "setup_go" in combined:
        return "go"
    if "setup_deb822_repo" in combined:
        return "apt-repo"
    if "setup_php" in combined or "composer" in combined:
        return "php"
    if "setup_postgresql" in combined or "setup_mariadb" in combined:
        return "database"
    if "fetch_and_deploy_gh_release" in combined:
        if "\"prebuild\"" in combined:
            target_match = re.search(r'fetch_and_deploy_gh_release[^"]*"prebuild"[^"]*"latest"[^"]*"([^"]*)"', install_content or "")
            target = target_match.group(1) if target_match else "/opt"
            if "/usr/local/bin" in target:
                return "single-binary"
            return "prebuild-tarball"
        return "tarball"
    return "custom"

def make_install_script(code, content, install_content, pattern):
    """Extract and transform the install logic."""
    if not install_content:
        return "# OS template — build_container handles setup/teardown\n"
    
    lines = install_content.split('\n')
    # Strip upstream framework boilerplate
    result = []
    skip_lines = False
    for line in lines:
        if re.match(r'^\s*source ', line):
            continue
        if line.strip() in ('color', 'verb_ip6', 'catch_errors', 'setting_up_container', 'network_check', 'update_os',
                           'motd_ssh', 'customize', 'cleanup_lxc'):
            continue
        
        # Fix arch_resolve -> get_system_arch
        line = re.sub(r'\$\(arch_resolve\s+"([^"]*)"\s+"([^"]*)"\)', '$(get_system_arch)', line)
        line = re.sub(r'\$\(arch_resolve\s+"([^"]*)"\)', '$(get_system_arch)', line)
        line = re.sub(r'arch_resolve\s+"([^"]*)"\s+"([^"]*)"', '$(get_system_arch)', line)
        
        # Fix x86_64 arch patterns where get_system_arch returns amd64
        # Check if original had x86_64 - if so, use uname approach
        if re.search(r'x86_64', line) and 'get_system_arch' in line:
            # Replace with uname-based detection
            line = line.replace('$(get_system_arch)', '${ARCH}')
            # ARCH needs to be set at top of install_script()
        
        if "SOURCES_LIST" in line:
            skip_lines = True
        if not skip_lines:
            result.append(line)
    
    code_clean = '\n'.join(result)
    
    # For PHP/FPM patterns, wrap in if block for ARCH if needed
    # For x86_64 patterns, add ARCH detection
    if re.search(r'x86_64', (install_content or '') + (content or '')):
        arch_block = '  ARCH=$(uname -m)\n  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"\n\n'
        code_clean = arch_block + code_clean
    
    # Remove empty lines at start
    code_clean = re.sub(r'^\s*\n', '', code_clean)
    code_clean = re.sub(r'\n{3,}', '\n\n', code_clean)
    
    return code_clean

def generate_script(slug, upstream_ct, upstream_install):
    """Generate the full migrated script content."""
    app = extract_app(upstream_ct) or slug.title()
    author = extract_author(upstream_ct)
    source, github = extract_source(upstream_ct)
    tags = extract_tags(upstream_ct)
    v = extract_var_defaults(upstream_ct)
    port = extract_port(upstream_ct)
    update_func = extract_update_function(upstream_ct)
    pattern = classify_pattern(upstream_ct, upstream_install)
    
    if not source:
        source = github
    
    install_code = make_install_script(None, upstream_ct, upstream_install, pattern)
    
    # Determine var_arm64
    var_arm64 = "yes" if v.get("var_arm64", "").strip().lower() in ("yes", "y", "true") else "yes"
    
    # Determine if update exists and what it does
    has_update = bool(update_func)
    
    # Render the script
    parts = []
    parts.append('#!/usr/bin/env bash')
    parts.append(f'REPO_BASE="${{REPO_BASE:-{REPO}}}"')
    parts.append('')
    parts.append('# Sourced by lxc.bootstrap — never executed directly')
    parts.append('# Copyright (c) 2021-2026 community-scripts ORG')
    parts.append(f'# Author: {author}')
    parts.append(f'# License: MIT | {REPO}/LICENSE')
    parts.append(f'# Source: {source}')
    parts.append('')
    parts.append('# shellcheck disable=SC2034')
    parts.append('# Read by the framework - shellcheck cannot see the caller')
    parts.append(f'APP="{app}"')
    parts.append(f'var_tags="${{var_tags:-{";".join(tags)}}}"')
    parts.append(f'var_cpu="${{var_cpu:-{v.get("var_cpu", "2")}}}"')
    parts.append(f'var_ram="${{var_ram:-{v.get("var_ram", "1024")}}}"')
    parts.append(f'var_disk="${{var_disk:-{v.get("var_disk", "4")}}}"')
    parts.append('var_os="${var_os:-debian}"')
    parts.append('var_version="${var_version:-13}"')
    parts.append(f'var_arm64="${{var_arm64:-{var_arm64}}}"')
    parts.append('var_unprivileged="${var_unprivileged:-1}"')
    parts.append('')
    parts.append('function install_script() {')
    parts.append(install_code)
    parts.append('}')
    parts.append('')
    
    # post_install_script
    parts.append('function post_install_script() {')
    parts.append('  msg_ok "Completed Successfully!\\n"')
    parts.append('  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"')
    parts.append('  echo -e "${INFO}${YW} Access it using the following URL:${CL}"')
    if port:
        parts.append(f'  echo -e "${{TAB}}${{GATEWAY}}${{BGN}}http://${{IP}}:{port}${{CL}}"')
    else:
        parts.append('  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"')
    parts.append('}')
    parts.append('')
    
    # update_script
    if has_update:
        update_code = update_func
        # Transform update function calls
        update_code = re.sub(r'\$\(arch_resolve\s+"([^"]*)"\s+"([^"]*)"\)', '$(get_system_arch)', update_code)
        update_code = re.sub(r'\$\(arch_resolve\s+"([^"]*)"\)', '$(get_system_arch)', update_code)
        update_code = re.sub(r'header_info\s+"\$\{?APP\}?"', 'header_info', update_code)
        update_code = re.sub(r'^\s+header_info$', '  header_info', update_code, flags=re.MULTILINE)
        parts.append('function update_script() {')
        parts.append(update_code)
        parts.append('}')
    else:
        # No update needed / self-updating
        parts.append('function update_script() {')
        parts.append('  header_info')
        parts.append('  check_container_storage')
        parts.append('  check_container_resources')
        if 'adguard' in slug.lower() or 'whisparr' in slug.lower():
            parts.append('')
            parts.append('  msg_error "This application can only be updated via its web interface."')
            parts.append('  exit')
        else:
            parts.append('')
            parts.append('  msg_error "No update path available for this application."')
            parts.append('  exit')
        parts.append('}')
    parts.append('')
    parts.append('# framework bootstrap')
    parts.append('# shellcheck disable=SC1090')
    parts.append('# Dynamic URL resolved at runtime - shellcheck cannot follow')
    parts.append('source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")')
    parts.append('')
    
    result = '\n'.join(parts)
    
    # Fix: remove duplicate newlines
    result = re.sub(r'\n{3,}', '\n\n', result)
    
    return result, pattern, app, port, tags, author

def generate_metadata(slug, app, tags, author, port, source_url, github_url):
    description_map = {}
    
    parts_text = []
    parts_text.append('---')
    parts_text.append(f'slug: {slug}')
    parts_text.append(f'title: {app}')
    parts_text.append(f'tags: [{", ".join(tags)}]')
    parts_text.append(f'logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/{slug}.webp')
    parts_text.append(f'by: {author.split("(")[0].strip() if "(" in author else author.split()[0]}')
    clean_gh = github_url if github_url else f"https://github.com/"
    parts_text.append(f'repo: {clean_gh}')
    parts_text.append(f'site: {source_url}')
    if port:
        parts_text.append(f'port: {port}')
    else:
        parts_text.append('port: 0')
    parts_text.append(f'cpu: 1')
    parts_text.append(f'ram: 512')
    parts_text.append(f'disk: 2')
    parts_text.append(f'maintainer: {author.split("(")[0].strip() if "(" in author else author.split()[0]}')
    parts_text.append('---')
    parts_text.append('')
    parts_text.append(f'{app} — migrated from community-scripts/ProxmoxVE.')
    parts_text.append('')
    parts_text.append('## Notes')
    parts_text.append('')
    parts_text.append('- Migrated from community-scripts upstream.')
    parts_text.append('- Verify configuration after first install.')
    parts_text.append('')
    parts_text.append('## Links')
    parts_text.append('')
    parts_text.append(f'- [GitHub]({clean_gh})')
    parts_text.append(f'- [Source]({source_url})')
    
    return '\n'.join(parts_text)

def check_logo(slug):
    url = f"https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/{slug}.webp"
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            return r.status == 200
    except Exception:
        return False

def main():
    dry_run = "--dry-run" in sys.argv
    
    # Load missing list
    with open("/tmp/missing-lxc.txt") as f:
        missing = [line.strip() for line in f if line.strip()]
    
    # Already done
    done = {"2fauth"}  # Already migrated in previous session
    
    start_from = 0
    for arg in sys.argv[1:]:
        if arg.startswith("--start-from="):
            start_from = int(arg.split("=")[1])
    
    count = 0
    for i, slug in enumerate(missing):
        if i < start_from:
            continue
        if slug in done:
            continue
        
        count += 1
        print(f"\n{'='*60}")
        print(f"#{i+1}/{len(missing)}: {slug}")
        print(f"{'='*60}")
        
        # Check if already exists
        script_path = SCRIPT_DIR / f"{slug}.sh"
        meta_path = META_DIR / f"{slug}.md"
        if script_path.exists() or meta_path.exists():
            print(f"  SKIP: already exists locally")
            continue
        
        # Fetch upstream
        ct = fetch(f"{UPSTREAM}/ct/{slug}.sh")
        if not ct:
            print(f"  SKIP: no upstream ct/{slug}.sh")
            continue
        install = fetch(f"{UPSTREAM}/install/{slug}-install.sh")
        
        # Check if it's an alpine variant
        is_alpine = slug.startswith("alpine-") or slug == "alpine"
        
        if is_alpine:
            print(f"  PATTERN: alpine variant — OS template")
            # Alpine variants are separate scripts that need different handling
            # Skip for now, focus on Debian-based
            print(f"  SKIP: alpine variant (handled separately)")
            continue
        
        # Generate script
        try:
            script_content, pattern, app, port, tags, author = generate_script(slug, ct, install or "")
            meta_content = generate_metadata(slug, app, tags, author, port, extract_source(ct)[0], extract_source(ct)[1])
        except Exception as e:
            print(f"  ERROR generating: {e}")
            continue
        
        # Check logo
        logo_ok = check_logo(slug)
        if not logo_ok:
            print(f"  WARN: no selfhst logo for {slug}")
        
        # Write files
        if not dry_run:
            SCRIPT_DIR.mkdir(parents=True, exist_ok=True)
            META_DIR.mkdir(parents=True, exist_ok=True)
            script_path.write_text(script_content)
            meta_path.write_text(meta_content)
            
            # Validate with devcontainer
            result = sh(f"docker exec -w /workspaces/scripts-underground-proxmox intelligent_albattani shfmt -i 2 -ci -sr -d scripts/lxc/{slug}.sh", check=False, capture=True)
            if result.returncode != 0:
                print(f"  SHFMT issues, fixing...")
                sh(f"docker exec -w /workspaces/scripts-underground-proxmox intelligent_albattani shfmt -i 2 -ci -sr -w scripts/lxc/{slug}.sh", check=False)
            
            result = sh(f"docker exec -w /workspaces/scripts-underground-proxmox intelligent_albattani shellcheck --severity=warning scripts/lxc/{slug}.sh", check=False, capture=True)
            if result.returncode != 0:
                print(f"  SHELLCHECK issues:")
                for line in result.stdout.split('\n')[:20]:
                    print(f"    {line}")
                # Try to fix common issues
                # Read, fix cd, rewrite
                current = script_path.read_text()
                current = re.sub(r'(?<!\|\| )cd /', 'cd /', current)  # won't work perfectly
                script_path.write_text(current)
            
            # Re-check after fixes
            result = sh(f"docker exec -w /workspaces/scripts-underground-proxmox intelligent_albattani shellcheck --severity=warning scripts/lxc/{slug}.sh", check=False, capture=True)
            if result.returncode != 0:
                print(f"  SHELLCHECK still failing — skipping commit")
                # Remove files
                script_path.unlink(missing_ok=True)
                meta_path.unlink(missing_ok=True)
                continue
            
            # Regenerate AST
            sh(f"docker exec -w /workspaces/scripts-underground-proxmox/tools/ast intelligent_albattani go run .", check=False)
            
            # Commit
            r = sh(f"git add scripts/lxc/{slug}.sh _lxc/{slug}.md", check=False, capture=True)
            if r.returncode != 0:
                print(f"  GIT ADD failed")
                continue
            
            r = sh(f'git commit -m "feat(lxc): add {app} migration from community-scripts"', check=False, capture=True)
            if r.returncode != 0:
                print(f"  GIT COMMIT failed: {r.stderr[:200]}")
                # Unstage
                sh(f"git restore --staged scripts/lxc/{slug}.sh _lxc/{slug}.md", check=False)
                continue
            
            r = sh(f"git push origin main", check=False, capture=True)
            if r.returncode != 0:
                print(f"  GIT PUSH failed: {r.stderr[:200]}")
                # Commit exists locally but not pushed — will be handled next iteration
            else:
                print(f"  ✅ PUSHED successfully")
            
            # Update log
            commit_hash = subprocess.run("git rev-parse --short HEAD", shell=True, capture_output=True, text=True).stdout.strip()
            pattern_label = pattern.replace('-', ' ').title()
            with open(LOG_FILE, 'a') as f:
                f.write(f'| {i+1} | 2026-07-19 | {slug} | {app} | {pattern_label} | ✅ | {commit_hash} |\n')
            
            # Also push log
            sh(f"git add MIGRATION-LOG.md", check=False)
            sh(f'git commit -m "chore: update migration log for {slug}"', check=False)
            sh(f"git push origin main", check=False)
            
            print(f"  ✅ {app} ({slug}) — {pattern_label}")
            
            # Small delay to avoid GitHub rate limits
            time.sleep(2)
        else:
            print(f"  [DRY RUN] Would migrate {app} ({slug}) — {pattern}")
    
    print(f"\n{'='*60}")
    print(f"Done. Processed {count} scripts.")

if __name__ == "__main__":
    main()
