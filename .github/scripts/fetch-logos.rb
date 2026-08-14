#!/usr/bin/env ruby
require 'yaml'
require 'fileutils'
require 'base64'
require 'tempfile'
require 'mini_magick'
require 'net/http'
require 'uri'

COLLECTIONS = {
  'lxc' => '_lxc',
  'addon' => '_addon',
  'pve' => '_pve',
  'vm' => '_vm'
}.freeze

LOGOS_DIR = 'assets/logos'
MAX_FILE_SIZE = 10 * 1024 * 1024
TIMEOUT_SECONDS = 5
MAX_REDIRECTS = 5

pr_dir = ENV['PR_DIR'] || '.'
logos_dir = File.join(pr_dir, LOGOS_DIR)
FileUtils.mkdir_p(logos_dir)

def slug_safe(name)
  clean = name.downcase.strip
  clean = clean.gsub(/\s+/, '-')
  clean = clean.gsub(/[^a-z0-9\-_]/, '')
  clean.empty? ? nil : clean
end

def download_remote(url)
  # TODO(security): revisit whether to reject HTTPS->HTTP downgrades on redirect.
  # Currently permissive to match curl -L; threat surface is bounded to logo bytes.
  current = url
  MAX_REDIRECTS.times do
    uri = URI.parse(current)
    raise "Invalid protocol" unless %w[http https].include?(uri.scheme)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = TIMEOUT_SECONDS
    http.read_timeout = TIMEOUT_SECONDS

    body = nil
    redirect_to = nil
    http.request(Net::HTTP::Get.new(uri)) do |response|
      case response.code
      when '200'
        buffer = String.new
        response.read_body do |chunk|
          buffer << chunk
          raise "File too large (>10MB)" if buffer.bytesize > MAX_FILE_SIZE
        end
        body = buffer
      when '301', '302', '303', '307', '308'
        loc = response['location']
        raise "Redirect without Location" if loc.nil? || loc.empty?
        redirect_to = URI.join(current, loc).to_s
      else
        raise "HTTP #{response.code}"
      end
    end

    return body if body
    current = redirect_to if redirect_to
  end
  raise "Too many redirects (#{MAX_REDIRECTS})"
end

def looks_like_svg?(bytes)
  head = bytes.byteslice(0, 512).to_s
  head.include?('<svg')
end

def rasterize_svg(svg_bytes)
  # ImageMagick's SVG delegate is disabled by Ubuntu's policy.xml, so
  # rasterize with librsvg first and hand the PNG to MiniMagick.
  # rsvg-convert doesn't fetch remote resources or execute embedded JS.
  Tempfile.create(['logo', '.svg']) do |tmp|
    tmp.binmode
    tmp.write(svg_bytes)
    tmp.flush
    png = IO.popen(['rsvg-convert', '-w', '1024', '-h', '1024', '-a', tmp.path], 'rb', &:read)
    raise "rsvg-convert failed (exit #{$?.exitstatus})" unless $?&.success?
    png
  end
end

COLLECTIONS.each_value do |dir|
  full_dir = File.join(pr_dir, dir)
  next unless Dir.exist?(full_dir)

  Dir.glob(File.join(full_dir, '*.md')).each do |file|
    content = File.read(file)
    next unless content =~ /\A---\s*\n(.*?\n)---\s*\n(.*)/m
    frontmatter = YAML.safe_load($1) || {}
    slug = frontmatter['slug'] || File.basename(file, '.md')
    url = frontmatter['logo']
    next unless url && !url.empty?

    safe_slug = slug_safe(slug)
    next unless safe_slug

    webp_path = File.join(logos_dir, "#{safe_slug}.webp")
    webp_url = "/#{LOGOS_DIR}/#{safe_slug}.webp"

    if url == webp_url
      puts "  already set: #{safe_slug}.webp"
      next
    end

    image_data = nil

    if url.start_with?('data:image/')
      puts "  decoding: #{safe_slug} (base64)"
      b64 = url.sub(/^data:image\/[a-z+]+;base64,/, '')
      image_data = Base64.decode64(b64)
    elsif url.start_with?('http://', 'https://')
      puts "  fetching: #{safe_slug} (#{url})"
      begin
        image_data = download_remote(url)
      rescue => e
        puts "    failed: #{e.message}"
        next
      end
    else
      next
    end

    if looks_like_svg?(image_data)
      puts "    rasterizing SVG via rsvg-convert"
      begin
        image_data = rasterize_svg(image_data)
      rescue => e
        puts "    SVG rasterization failed: #{e.message}"
        next
      end
    end

    begin
      image = MiniMagick::Image.read(image_data)
      image.combine_options do |c|
        c.background "none"
        c.resize "512x512"
        c.gravity "center"
        c.extent "512x512"
      end
      image.format "webp"
      image.write webp_path
      puts "    saved: #{webp_path} (#{File.size(webp_path)} bytes)"
    rescue => e
      puts "    conversion failed: #{e.message}"
      File.delete(webp_path) if File.exist?(webp_path)
      next
    end

    new_content = content.sub(/^(logo:\s*)\S+/, "\\1#{webp_url}")
    File.write(file, new_content) if new_content != content
  end
end

puts "Done"
