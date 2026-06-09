require 'json'
require 'yaml'

COLLECTIONS = {
  'lxc' => '_lxc',
  'addon' => '_addon',
  'pve' => '_pve',
  'vm' => '_vm'
}.freeze

def repo_info
  if ENV['GITHUB_REPOSITORY'] =~ /\A(.+)\/(.+)\z/
    [$1, $2]
  elsif `git remote get-url origin 2>/dev/null` =~ %r{[:/](.+)/(.+)\.git\z}
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

Jekyll::Hooks.register :site, :post_write do |site|
  root = site.source
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
      updatable = File.exist?(script_file) && File.read(script_file).match?(/^\s*function\s+update_script|^\s*update_script\s*\(\)/)
      created = begin
        t1 = File.ctime(file) rescue Time.at(0)
        t2 = File.exist?(script_file) ? (File.ctime(script_file) rescue Time.at(0)) : Time.at(0)
        [t1, t2].min.iso8601
      end
      updated = begin
        t1 = File.mtime(file)
        t2 = File.exist?(script_file) ? File.mtime(script_file) : t1
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
        updatable: updatable
      }
    end
  end

  output = JSON.pretty_generate({
    meta: { generated_at: Time.now.utc.iso8601, total: scripts.size },
    commands: mirrors.keys,
    scripts: scripts
  })

  File.write(File.join(site.dest, 'scripts.json'), output)
end
