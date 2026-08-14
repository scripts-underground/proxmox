#!/usr/bin/env ruby
# tools/validate-logos.rb — validate/auto-fix logo files changed in a PR.
#
# Runs in CI after fetch-logos. For each added/modified file under assets/logos/:
#   - unreadable / not an image      → HARD FAIL (exit 1)
#   - not webp                       → auto-fix: convert to webp, remove original
#   - not 512x512                    → auto-fix: resize + extent (alpha-safe order)
#   - no alpha + all-white corners   → WARN (possible alpha-flattening bug;
#                                     may be an intentional white background)
#
# Auto-fixes land via the workflow's existing "Commit generated artifacts"
# step (it stages assets/logos/). Warnings and failures go to stdout so they
# surface in the PR checks log.

require 'mini_magick'
require 'open3'

LOGOS_DIR = 'assets/logos'
BASE = ENV['GITHUB_BASE_REF'] || 'main'

# Two-dot diff against origin/<base> (no ...HEAD) so both committed changes
# and uncommitted working-tree changes from fetch-logos are validated in the
# same run.
out, = Open3.capture2('git', 'diff', '--name-only', '--diff-filter=AM',
                      "origin/#{BASE}", '--', LOGOS_DIR)
changed = out.split("\n").select { |f| File.exist?(f) }

if changed.empty?
  puts 'No changed logo files — nothing to validate.'
  exit 0
end

failures = []
warnings = []
fixed = []

changed.each do |path|
  # --- hard fail: not a readable image -------------------------------------
  begin
    img = MiniMagick::Image.open(path)
    img.identify
  rescue StandardError => e
    failures << "#{path}: not a readable image (#{e.message})"
    next
  end

  # --- auto-fix: format must be webp ---------------------------------------
  unless path.end_with?('.webp')
    webp_path = path.sub(/\.\w+\z/, '.webp')
    img.format 'webp'
    img.write webp_path
    File.delete(path)
    fixed << "#{path} → #{webp_path} (format)"
    path = webp_path
    img = MiniMagick::Image.open(path)
  end

  # --- auto-fix: dimensions must be 512x512 ---------------------------------
  w = img.width
  h = img.height
  if w != 512 || h != 512
    img.combine_options do |c|
      c.background 'none' # MUST come before extent or alpha flattens
      c.resize '512x512'
      c.gravity 'center'
      c.extent '512x512'
    end
    img.write path
    fixed << "#{path} (resized #{w}x#{h} → 512x512)"
    img = MiniMagick::Image.open(path)
  end

  # --- warn: alpha-flattening signature ------------------------------------
  # get_pixels works on both IM6 (convert/identify) and IM7 (magick) CI images.
  pixels = img.get_pixels
  has_alpha = pixels.first.first.length >= 4
  unless has_alpha
    scale = pixels.flatten.max.to_i > 255 ? 65_535 : 255
    white_thresh = (scale * 0.98).to_i
    corners = [pixels[0][0], pixels[0][-1], pixels[-1][0], pixels[-1][-1]]
    if corners.all? { |px| px[0] >= white_thresh && px[1] >= white_thresh && px[2] >= white_thresh }
      warnings << "#{path}: no alpha channel and all-white corners — " \
                  'looks like alpha was flattened in conversion (use `-background none` BEFORE `-extent`). ' \
                  'If this is an intentional white-background logo, ignore this warning.'
    end
  end

  puts "OK: #{path}"
end

puts
fixed.each     { |m| puts "[fixed]  #{m}" }
warnings.each  { |m| puts "[warn]   #{m}" }
failures.each  { |m| puts "[FAIL]   #{m}" }
puts
puts "#{changed.size} checked, #{fixed.size} auto-fixed, #{warnings.size} warnings, #{failures.size} failures"

exit(failures.empty? ? 0 : 1)
