require 'nokogiri'
require 'zlib'
require 'cgi'
require 'uri'
require_relative '../dor'

XPATH_FN_NS = "http://www.w3.org/2005/xpath-functions"
QUI_NS = "http://dlxs.org/quombat/ui"
NSMAP = {
  'fn' => XPATH_FN_NS,
  'qui' => QUI_NS,
  'glam' => "urn:umich:lib:dor:model:2026:resource:glam"
}

# Register a custom function under a specific namespace URI
Nokogiri::XSLT.register("urn:umich:lib:dor:model:2026:resource:glam", Class.new do
  def hash_id(input)
    # The input from XSLT is often a NodeSet or an Array; 
    # we convert to string to hash it.
    str = input.is_a?(Enumerable) ? input.first.to_s : input.to_s
    DOR::to_xml_id(str.downcase)
  end

  def basename(input)
    str = input.is_a?(Enumerable) ? input.first.to_s : input.to_s
    File.basename(str, ".*").downcase
  end

  def from_cgi(input)
    str = input.is_a?(Enumerable) ? input.first.to_s : input.to_s
    uri = URI.parse(str)
    params = CGI.parse(uri.query)
    File.basename(params["viewid"].first.downcase, ".*")
  end
end)
