#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'nokogiri'
require 'json'
require 'http'
require 'builder'
require 'pp'

require_relative '../lib/dor'
require_relative '../lib/dor/headers'
require_relative "../lib/dlxs"
require_relative "../lib/dlxs/utils"
require_relative "../lib/dlps_utils"
require_relative "../lib/cache"

require_relative '../lib/dlxs/cgi/text'

# Register a custom function under a specific namespace URI
Nokogiri::XSLT.register("urn:umich:lib:dor:model:2026:resource:glam", Class.new do
  def hash_id(input)
    # The input from XSLT is often a NodeSet or an Array; 
    # we convert to string to hash it.
    str = input.is_a?(Enumerable) ? input.first.to_s : input.to_s
    STDERR.puts "== hashing #{str}"
    DOR::to_xml_id(str.downcase)
  end
end)

XPATH_FN_NS = "http://www.w3.org/2005/xpath-functions"
QUI_NS = "http://dlxs.org/quombat/ui"
TEI_NS = "http://www.tei-c.org/ns/1.0"
NSMAP = {
  'fn' => XPATH_FN_NS,
  'qui' => QUI_NS,
  'tei' => TEI_NS,
  'glam' => "urn:umich:lib:dor:model:2026:resource:glam"
}

options = OpenStruct.new()
options.dlxs_host = "quod.lib.umich.edu"

OptionParser.new do |opts|
  opts.on("-c", "--collid COLLID", "Collection ID") do |c|
    options.collid = c
  end
  opts.on("--idno IDNO", "IDNO") do |c|
    options.idno = c.downcase
  end
  opts.on("--partner PARTNER", "partner") do |c|
    options.partner = c
  end
  opts.on("--output_path OUTPUT_PATH", "output path") do |c|
    options.output_path = c
  end
  opts.on("--host HOST", "DLXS host") do |c|
    options.dlxs_host = c
  end  
end.parse!

if options.partner.nil?
  options.partner = options.collid
end

Random.srand(1001)

Cache.new(options.collid, "https://#{options.dlxs_host}/cgi/t/text") do |cache|
  local_identifier = "#{options.collid}.#{options.idno}"
  submission = DOR::Submission.new(output_path: options.output_path, local_identifier: local_identifier)
  STDERR.puts ":: exporting to #{submission.submission_path}"
  context = DLXS::CGI::Context.new(
    collid: options.collid,
    partner: options.partner,
    idno: options.idno,
    cache: cache,
    submission: submission
  )
  generator = DLXS::CGI::Text.new(context: context)
  generator.export_submission
end
