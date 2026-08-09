#!/usr/bin/env ruby
# Standalone regenerator for scripts.json — mirrors _plugins/scripts_json.rb's
# post-write hook without Jekyll's overhead. Prints per-file progress.
#
# Run from repo root or anywhere; script resolves paths from its own location:
#   ruby tools/regen-scripts-json.rb
require 'json'
require 'yaml'
require 'open3'
require 'time'

COLLECTIONS = {
  'lxc'   => '_lxc',
  'addon' => '_addon',
  'pve'   => '_pve',
  'vm'    => '_vm'
}.freeze

def repo_info
  if ENV['GITHUB_REPOSITORY'] =~ /\A(.+)\/(.+)\z/
    [$1, $2]
  elsif begin
    remote_url, status = Open3.capture2('git', 'remote', 'get-url', 'origin')
    status.success? && remote_url.strip =~ %r{[:/](.+)/(.+)\.git\z}
  rescue
    nil
  end
    [$1, $2]
  else
    ['scripts-underground', 'proxmox']
  end
end

def load_mirrors(root)
  defaults = {
    'github'   => { 'url' => 'https://raw.githubusercontent.com/{owner}/{repo}/main' },
    'codeberg' => { 'url' => 'https://codeberg.org/{owner}/{repo}/raw/branch/main' }
  }
  mirror_file = File.join(root, '_data', 'mirrors.yml')
  custom = File.exist?(mirror_file) ? (YAML.load_file(mirror_file) || {}) : {}
  defaults.merge(custom)
end

def install_cmd(base_url, type, slug)
  "REPO_BASE=#{base_url} bash -c \"$(curl -fsSL #{base_url}/scripts/#{type}/#{slug}.sh)\""
end

# Phase 1: build the git-log index. One subprocess (git log via exec, no
# shell). Streams stdout. Block form auto-waits and provides exit status.
# Runs to completion before any per-file iteration begins.
def build_git_index
  last_touched  = {}
  first_touched = {}
  current_time  = nil
  STDERR.puts "Building git-log index..."
  started = Time.now
  Open3.popen2('git', 'log', '--format=@@@%cI', '--name-only') do |_stdin, stdout, wait_thr|
    stdout.each_line do |line|
      line.chomp!
      if line.start_with?('@@@')
        current_time = line[3..]
      elsif !line.empty?
        last_touched[line]  ||= current_time
        first_touched[line]   = current_time
      end
    end
    raise "git log failed with #{wait_thr.value.exitstatus}" unless wait_thr.value.success?
  end
  STDERR.puts "  #{last_touched.size} files indexed in #{(Time.now - started).round(2)}s"
  [first_touched, last_touched]
end

def git_date(rel_path, mode, index_first, index_last)
  index = mode == :first ? index_first : index_last
  ts = index[rel_path]
  ts && Time.parse(ts)
rescue
  nil
end

root = File.expand_path('..', __dir__)
Dir.chdir(root)

first_touched, last_touched = build_git_index

owner, repo = repo_info
mirrors = load_mirrors(root)
scripts = []
started = Time.now

COLLECTIONS.each do |type, dir|
  files = Dir.glob(File.join(root, dir, '*.md')).sort
  puts "[#{type}] #{files.size} entries"

  files.each_with_index do |file, i|
    slug_default = File.basename(file, '.md')
    printf "  %4d/%d  [%s] %-40s ", i + 1, files.size, type, slug_default
    STDOUT.flush
    entry_started = Time.now

    content = File.read(file)
    unless content =~ /\A---\s*\n(.*?\n)---\s*\n(.*)/m
      puts "SKIP (no frontmatter)"
      next
    end
    frontmatter = YAML.safe_load($1) || {}
    body = $2.strip
    slug = frontmatter['slug'] || slug_default

    desc = body.gsub(/^#.*$/, '').strip.split(/\n\n+/).first
    desc = desc&.gsub(/\n/, ' ')&.strip || ''

    script_url  = "/scripts/#{type}/#{slug}.sh"
    script_file = File.join(root, "scripts/#{type}/#{slug}.sh")

    hooks = {}
    has_docker = false
    has_podman = false
    has_external = false
    has_download = false
    has_piped_download = false
    has_git = false
    has_npm = false
    has_yarn = false
    has_pnpm = false
    has_pip = false
    has_cargo = false
    has_go = false
    has_sudo = false
    has_eval = false
    has_global = false
    hook_order = []
    overrides = []
    systemd_services = nil
    openrc_services = nil
    service_managers = nil
    users = nil
    interactive_prompts = nil

    if File.exist?(script_file)
      ast_file = File.join(root, "_ast/#{type}/#{slug}.json")
      unless File.exist?(ast_file)
        puts "FAIL (missing AST #{ast_file})"
        exit 1
      end
      ast = JSON.parse(File.read(ast_file))
      hooks = ast['hooks'] || {}
      hook_order = ast['hook_order'] || []
      flags = ast['flags'] || {}
      has_docker = flags['docker'] == true
      has_podman = flags['podman'] == true
      has_external = ast['has_external'] == true
      has_download = ast['has_download'] == true
      has_piped_download = ast['has_piped_download'] == true
      has_git = flags['git'] == true
      has_npm = flags['npm'] == true
      has_yarn = flags['yarn'] == true
      has_pnpm = flags['pnpm'] == true
      has_pip = flags['pip'] == true
      has_cargo = flags['cargo'] == true
      has_go = flags['go'] == true
      has_sudo = flags['sudo'] == true
      has_eval = flags['eval'] == true
      has_global = ast['has_global'] == true
      overrides = (ast['assigns'] || []).select { |a|
        a['name'].start_with?('var_') && a['value_is_param_default']
      }.map { |a| a['name'] }.uniq.sort
      systemd_services = ast['systemd_services']
      openrc_services = ast['openrc_services']
      service_managers = ast['service_managers']
      users = ast['users']
      interactive_prompts = ast['interactive_prompts']
      pinned_commit = nil
      has_pc = false
      pc = (ast['assigns'] || []).find { |a| a['name'] == 'var_lxc_pinned_commit' || a['name'] == 'var_pinned_commit' }
      if pc
        has_pc = true
        line = ast['source_lines'][pc['line'] - 1]
        if line =~ /\$\{var_(?:lxc_)?pinned_commit:-([^}]*)\}/
          raw = $1.strip
          pinned_commit = raw unless raw.empty?
        end
      end
      git_repo = nil
      has_gr = false
      gr = (ast['assigns'] || []).find { |a| a['name'] == 'var_lxc_git_repo' || a['name'] == 'var_git_repo' }
      if gr
        has_gr = true
        line = ast['source_lines'][gr['line'] - 1]
        if line =~ /\$\{var_(?:lxc_)?git_repo:-([^}]*)\}/
          raw = $1.strip
          git_repo = raw unless raw.empty?
        end
      end
      git_branch = nil
      has_gb = false
      gb = (ast['assigns'] || []).find { |a| a['name'] == 'var_lxc_git_branch' || a['name'] == 'var_git_branch' }
      if gb
        has_gb = true
        line = ast['source_lines'][gb['line'] - 1]
        if line =~ /\$\{var_(?:lxc_)?git_branch:-([^}]*)\}/
          raw = $1.strip
          git_branch = raw unless raw.empty?
        end
      end
      git_tag = nil
      has_gt = false
      gt = (ast['assigns'] || []).find { |a| a['name'] == 'var_lxc_git_tag' || a['name'] == 'var_git_tag' }
      if gt
        has_gt = true
        line = ast['source_lines'][gt['line'] - 1]
        if line =~ /\$\{var_(?:lxc_)?git_tag:-([^}]*)\}/
          raw = $1.strip
          git_tag = raw unless raw.empty?
        end
      end
    end

    relative_md = File.join(dir, File.basename(file))
    relative_sh = "scripts/#{type}/#{slug}.sh"

    created = begin
      t1 = git_date(relative_md, :first, first_touched, last_touched) || (File.ctime(file) rescue Time.at(0))
      t2 = File.exist?(script_file) ? (git_date(relative_sh, :first, first_touched, last_touched) || (File.ctime(script_file) rescue Time.at(0))) : Time.at(0)
      [t1, t2].min.iso8601
    end
    updated = begin
      t1 = git_date(relative_md, :last, first_touched, last_touched) || File.mtime(file)
      t2 = File.exist?(script_file) ? (git_date(relative_sh, :last, first_touched, last_touched) || File.mtime(script_file)) : t1
      [t1, t2].max.iso8601
    end

    installs = {}
    mirrors.each do |name, mirror|
      base = mirror['url'].gsub('{owner}', owner).gsub('{repo}', repo)
      installs[name] = install_cmd(base, type, slug)
    end

    scripts << {
      slug: slug,
      title: frontmatter['title'] || slug,
      type: type,
      tags: frontmatter['tags'] || [],
      by: frontmatter['by'],
      co_author: frontmatter['co_author'],
      repo: frontmatter['repo'],
      site: frontmatter['site'],
      port: frontmatter['port'],
      cpu: frontmatter['cpu'],
      ram: frontmatter['ram'],
      disk: frontmatter['disk'],
      pinned_commit: pinned_commit,
      has_pinned_commit: has_pc,
      git_repo: git_repo,
      has_git_repo: has_gr,
      git_branch: git_branch,
      has_git_branch: has_gb,
      git_tag: git_tag,
      has_git_tag: has_gt,
      image: frontmatter['image'],
      logo: frontmatter['logo'],
      description: desc,
      page: "/#{type}/#{slug}/",
      script: script_url,
      install: installs,
      created_at: created,
      updated_at: updated,
      hooks: hooks,
      hook_order: hook_order.any? ? hook_order : nil,
      has_docker: has_docker,
      has_podman: has_podman,
      has_external: has_external,
      has_download: has_download,
      has_piped_download: has_piped_download,
      has_sudo: has_sudo,
      has_eval: has_eval,
      has_git: has_git,
      has_npm: has_npm,
      has_yarn: has_yarn,
      has_pnpm: has_pnpm,
      has_pip: has_pip,
      has_cargo: has_cargo,
      has_go: has_go,
      has_global: has_global,
      overrides: overrides,
      systemd_services: systemd_services,
      openrc_services: openrc_services,
      service_managers: service_managers,
      users: users,
      interactive_prompts: interactive_prompts
    }

    elapsed = Time.now - entry_started
    printf "OK (%.2fs)\n", elapsed
  end
end

output = JSON.pretty_generate({
  meta:     { generated_at: Time.now.utc.iso8601, total: scripts.size },
  commands: mirrors.keys,
  scripts:  scripts
})
File.write(File.join(root, 'scripts.json'), output)

total_elapsed = Time.now - started
puts ""
puts "Wrote scripts.json with #{scripts.size} entries in #{total_elapsed.round(2)}s"
