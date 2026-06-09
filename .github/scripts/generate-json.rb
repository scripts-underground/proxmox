#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'time'

COLLECTIONS = {
  'lxc' => '_lxc',
  'addon' => '_addon',
  'pve' => '_pve',
  'vm' => '_vm'
}.freeze

def repo_info
  if ENV['GITHUB_REPOSITORY'] && ENV['GITHUB_REPOSITORY'] =~ /\A(.+)\/(.+)\z/
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
  custom = File.exist?('_data/mirrors.yml') ? (YAML.load_file('_data/mirrors.yml') || {}) : {}
  defaults.merge(custom)
end

def install_command(base_url, type, slug)
  "REPO_BASE=#{base_url} bash -c \"$(curl -fsSL #{base_url}/scripts/#{type}/#{slug}.sh)\""
end

system('git config --global safe.directory "*" 2>/dev/null')

owner, repo = repo_info
mirrors = load_mirrors

scripts = []

COLLECTIONS.each do |type, dir|
  Dir.glob("#{dir}/*.md").each do |file|
    content = File.read(file)
    if content =~ /\A---\s*\n(.*?\n)---\s*\n(.*)/m
      frontmatter = YAML.safe_load($1) || {}
      body = $2.strip
    else
      next
    end

    slug = frontmatter['slug'] || File.basename(file, '.md')

    desc = body
      .gsub(/^#.*$/, '')
      .strip
      .split(/\n\n+/)
      .first
      &.gsub(/\n/, ' ')
      &.strip || ''

    script_url = "/scripts/#{type}/#{slug}.sh"
    script_file = "scripts/#{type}/#{slug}.sh"
    updatable = File.exist?(script_file) && File.read(script_file).match?(/^\s*function\s+update_script|^\s*update_script\s*\(\)/)

    sh_file = script_file
    created = begin
      l = `git log --diff-filter=A --follow --format=%cI -- '#{file}' 2>/dev/null`.lines.first
      l&.strip
    rescue
      nil
    end || begin
      t1 = File.ctime(file) rescue Time.at(0)
      t2 = File.exist?(sh_file) ? (File.ctime(sh_file) rescue Time.at(0)) : Time.at(0)
      [t1, t2].min.iso8601
    end
    updated = begin
      l = `git log -1 --format=%cI -- '#{file}' '#{sh_file}' 2>/dev/null`.lines.first
      l&.strip
    rescue
      nil
    end || begin
      t1 = File.mtime(file)
      t2 = File.exist?(sh_file) ? File.mtime(sh_file) : t1
      [t1, t2].max.iso8601
    end

    installs = {}
    mirrors.each do |name, mirror|
      base = mirror['url'].gsub('{owner}', owner).gsub('{repo}', repo)
      installs[name] = install_command(base, type, slug)
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

output = {
  meta: {
    generated_at: Time.now.utc.iso8601,
    total: scripts.size
  },
  commands: mirrors.keys,
  scripts: scripts
}

File.write('scripts.json', JSON.pretty_generate(output))
puts "Generated scripts.json with #{scripts.size} scripts, #{mirrors.size} mirrors"
