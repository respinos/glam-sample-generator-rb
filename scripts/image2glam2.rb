#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'

require_relative '../lib/dlxs'
require_relative '../lib/dlxs/utils'
require_relative '../lib/cache'
require_relative '../lib/dlxs/cgi/image'

options = OpenStruct.new()
options.output_path = "examples"
options.dlxs_host = "quod.lib.umich.edu"

OptionParser.new do |opts|
  opts.on("-c", "--collid COLLID", "Collection ID") do |c|
    options.collid = c
  end
  opts.on("--m_id M_ID", "m_id") do |c|
    options.m_id = c.downcase
  end
  opts.on("--partner PARTNER", "partner") do |c|
    options.partner = c.downcase
  end
  opts.on("--output_path OUTPUT_PATH", "output path") do |c|
    options.output_path = c
  end
  opts.on("--host HOST", "DLXS host") do |c|
    options.dlxs_host = c
  end
  opts.on("--debug", "debug mode") do |v|
    options.debug = v
  end
end.parse!

if options.partner.nil?
  options.partner = options.collid
end

Random.srand(1001)

Cache.new(options.collid, "https://#{options.dlxs_host}/cgi/i/image") do |cache|
  local_identifier = "#{options.collid}.#{options.m_id}"
  submission = DOR::Submission.new(output_path: options.output_path, local_identifier: local_identifier)
  STDERR.puts ":: exporting to #{submission.submission_path}"
  context = DLXS::CGI::Context.new(
    collid: options.collid,
    partner: options.partner,
    m_id: options.m_id,
    cache: cache,
    submission: submission
  )
  generator = DLXS::CGI::Image.new context: context
  generator.export_submission
end


puts "-30-"
