require 'json'
require 'fileutils'

# Thin loader — reads the pre-committed scripts.json produced by
# tools/regen-scripts-json.rb. No git, no frontmatter scanning,
# no generation. Sorted alphabetically by the tool.

Jekyll::Hooks.register :site, :post_read do |site|
  scripts_path = File.join(site.source, 'scripts.json')
  unless File.exist?(scripts_path)
    raise Jekyll::Errors::FatalException,
      "scripts.json not found"
  end

  data = JSON.parse(File.read(scripts_path))
  site.data['scripts_index'] = data
end

# Expose pinned_commit as document-level data so templates use
# the same path as cpu/ram/disk (page.pinned_commit).
Jekyll::Hooks.register :documents, :pre_render do |doc|
  scripts_path = File.join(doc.site.source, 'scripts.json')
  next unless File.exist?(scripts_path)

  scripts = JSON.parse(File.read(scripts_path))
  entry = scripts['scripts'].find { |s| s['slug'] == doc.data['slug'] }
  next unless entry

  doc.data['pinned_commit'] = entry['pinned_commit']
  doc.data['has_pinned_commit'] = entry['has_pinned_commit']
  doc.data['git_repo'] = entry['git_repo']
  doc.data['has_git_repo'] = entry['has_git_repo']
  doc.data['git_branch'] = entry['git_branch']
  doc.data['has_git_branch'] = entry['has_git_branch']
end

Jekyll::Hooks.register :site, :post_write do |site|
  scripts_src = File.join(site.source, 'scripts.json')
  scripts_dst = File.join(site.dest, 'scripts.json')
  FileUtils.cp(scripts_src, scripts_dst) if File.exist?(scripts_src)

  ast_src = File.join(site.source, '_ast')
  ast_dst = File.join(site.dest, 'ast')
  if File.exist?(ast_src)
    FileUtils.rm_rf(ast_dst) if File.exist?(ast_dst)
    FileUtils.cp_r(ast_src, ast_dst)
  end
end
