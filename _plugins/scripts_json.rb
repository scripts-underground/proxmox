require 'json'
require 'fileutils'

# Thin loader — reads the pre-committed scripts.json produced by
# tools/regen-scripts-json.rb. No git, no frontmatter scanning,
# no generation. Sorted alphabetically by the tool.

Jekyll::Hooks.register :site, :post_read do |site|
  scripts_path = File.join(site.source, 'scripts.json')
  unless File.exist?(scripts_path)
    raise Jekyll::Errors::FatalException,
      "scripts.json missing. Run: ruby tools/regen-scripts-json.rb"
  end

  data = JSON.parse(File.read(scripts_path))
  site.data['scripts_index'] = data
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
