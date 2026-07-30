require 'nokogiri'

Jekyll::Hooks.register([:documents], :post_render) do |doc|
  next unless doc.output
  frag = Nokogiri::HTML.fragment(doc.output)
  frag.css('a').each { |a| a['rel'] = 'noopener noreferrer' }
  doc.output = frag.to_html
end
