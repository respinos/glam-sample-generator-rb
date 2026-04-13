#!/usr/bin/env ruby

require 'ostruct'
require 'optparse'
require 'fileutils'
require 'json'
require 'nanoid'
require 'digest'
require 'pp'

require_relative '../lib/headers'

options = OpenStruct.new()
OptionParser.new do |opts|
  opts.on("--resource RESOURCE_PATH", "Path to resource file") do |v|
    options.resource_path = v
  end
end.parse!

if not File.exist?(options.resource_path)
  STDERR.puts "Resource file not found: #{options.resource_path}"
  exit(1)
end

remove_path = File.dirname(options.resource_path) + "/"
package_resources = Dir.glob(File.join(options.resource_path, "**", "core.dor.json")).select { |f| File.file?(f) }
package_resources.each do |core_path|
  resource_path = File.dirname(core_path)
  resource_id = resource_path.sub(remove_path, "")
  resource_files = Dir.glob(File.join(resource_path, "*")).select { |f| File.file?(f) }
  resource_files.each do |resource_file|
    header_file, header_data = Headers.generate_header(resource_id, resource_file)
    File.open(header_file, "w") do |f|
      f.write(JSON.pretty_generate(header_data))
    end
  end
end
