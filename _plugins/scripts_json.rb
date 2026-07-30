require 'json'
require 'yaml'
require 'fileutils'
require 'pathname'
require 'shellwords'
require 'time'
require 'open3'

COLLECTIONS = {
  'lxc' => '_lxc',
  'addon' => '_addon',
  'pve' => '_pve',
  'vm' => '_vm'
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

def load_mirrors
  defaults = {
    'github' => { 'url' => 'https://raw.githubusercontent.com/{owner}/{repo}/main' },
    'codeberg' => { 'url' => 'https://codeberg.org/{owner}/{repo}/raw/branch/main' }
  }
  mirror_file = File.join(File.dirname(__FILE__), '..', '_data', 'mirrors.yml')
  custom = File.exist?(mirror_file) ? (YAML.load_file(mirror_file) || {}) : {}
  defaults.merge(custom)
end

def install_cmd(base_url, type, slug)
  "REPO_BASE=#{base_url} bash -c \"$(curl -fsSL #{base_url}/scripts/#{type}/#{slug}.sh)\""
end

# Build an in-memory index of {file_path => oldest_iso_8601_date} from a
# single git-log pass. One subprocess (via Open3, no shell), block form
# auto-waits for exit. Used by git_date() below.
def build_git_log_index
  first_touched = {}
  last_touched = {}
  current_time = nil
  Open3.popen2('git', 'log', '--format=@@@%cI', '--name-only') do |_stdin, stdout, wait_thr|
    stdout.each_line do |line|
      line.chomp!
      if line.start_with?('@@@')
        current_time = line[3..]
      elsif !line.empty?
        last_touched[line] ||= current_time
        first_touched[line] = current_time
      end
    end
    raise "git log failed with #{wait_thr.value.exitstatus}" unless wait_thr.value.success?
  end
  [first_touched, last_touched]
end

# Resolve repo-relative path (same format git emits in --name-only output).
def git_date(file, mode, index_first, index_last)
  index = mode == :first ? index_first : index_last
  # Convert absolute path to repo-relative, falling back to the raw path.
  rel = begin
    Pathname.new(file).relative_path_from(Pathname.new(Dir.pwd)).to_s
  rescue
    file
  end
  ts = index[rel]
  ts && Time.parse(ts)
rescue
  nil
end

Jekyll::Hooks.register :site, :post_write do |site|
  root = site.source
  index_first, index_last = build_git_log_index
  owner, repo = repo_info
  mirrors = load_mirrors

  scripts = []

  COLLECTIONS.each do |type, dir|
    Dir.glob(File.join(root, dir, '*.md')).each do |file|
      content = File.read(file)
      next unless content =~ /\A---\s*\n(.*?\n)---\s*\n(.*)/m
      frontmatter = YAML.safe_load($1) || {}
      body = $2.strip
      slug = frontmatter['slug'] || File.basename(file, '.md')

      desc = body.gsub(/^#.*$/, '').strip.split(/\n\n+/).first
      desc = desc&.gsub(/\n/, ' ')&.strip || ''

      script_url = "/scripts/#{type}/#{slug}.sh"

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

      if File.exist?(script_file)
        ast_file = File.join(root, "_ast/#{type}/#{slug}.json")
        unless File.exist?(ast_file)
          raise "Missing AST file #{ast_file}. Run `go run ./tools/ast/.` to generate."
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
      end

      created = begin
        t1 = git_date(file, :first, index_first, index_last) || (File.ctime(file) rescue Time.at(0))
        t2 = File.exist?(script_file) ? (git_date(script_file, :first, index_first, index_last) || (File.ctime(script_file) rescue Time.at(0))) : Time.at(0)
        [t1, t2].min.iso8601
      end
      updated = begin
        t1 = git_date(file, :last, index_first, index_last) || File.mtime(file)
        t2 = File.exist?(script_file) ? (git_date(script_file, :last, index_first, index_last) || File.mtime(script_file)) : t1
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
    end
  end

  output = JSON.pretty_generate({
    meta: { generated_at: Time.now.utc.iso8601, total: scripts.size },
    commands: mirrors.keys,
    scripts: scripts
  })

  File.write(File.join(site.dest, 'scripts.json'), output)
  File.write(File.join(site.source, 'scripts.json'), output)

  # Copy AST files for client-side consumption
  ast_src = File.join(root, '_ast')
  ast_dst = File.join(site.dest, 'ast')
  if File.exist?(ast_src)
    FileUtils.rm_rf(ast_dst) if File.exist?(ast_dst)
    FileUtils.cp_r(ast_src, ast_dst)
  end
end
