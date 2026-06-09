require 'nokogiri'

TAG_RE = /<[^>]+>/
IMG_RE = /!\[[^\]]*\]\([^)]*\)/

Jekyll::Hooks.register([:documents], :pre_render) do |doc|
  return unless doc.content
  doc.content = doc.content.gsub(TAG_RE, '').gsub(IMG_RE, '')
end

Jekyll::Hooks.register([:documents], :post_render) do |doc|
  next unless doc.output
  frag = Nokogiri::HTML.fragment(doc.output)
  frag.css('a').each { |a| a['rel'] = 'noopener noreferrer' }
  doc.output = frag.to_html
end
