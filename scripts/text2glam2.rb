#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'

require_relative "../lib/dlxs"
require_relative "../lib/dlxs/utils"
require_relative "../lib/cache"
require_relative '../lib/dlxs/cgi/text'

options = OpenStruct.new()
options.dlxs_host = "quod.lib.umich.edu"
options.do_bundle = false

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
  opts.on("--debug", "debug mode") do |v|
    options.debug = v
  end
  opts.on("--bundle", "bundle submission") do |v|
    options.do_bundle = true
  end
  opts.on("--no-bundle", "do not bundle submission") do |v|
    options.do_bundle = false
  end
end.parse!

if options.partner.nil?
  options.partner = options.collid
end

Random.srand(1001)

Cache.new(options.collid, "https://#{options.dlxs_host}/cgi/t/text") do |cache|
  local_identifier = options.idno
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
  submission.bundle if options.do_bundle
end
