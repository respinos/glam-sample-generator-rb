#!/usr/bin/env ruby

#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'nokogiri'
require 'json'

options = OpenStruct.new()
package_path = nil

OptionParser.new do |opts|
  opts.on("--package_path PACKAGE_PATH", "Package path") do |v|
    package_path = v
  end
end.parse!

data_path = File.join(package_path, "data")
events_path = File.join(package_path, "events")

events_data_source = {}
events_data_outcome = {}

Dir.glob(File.join(events_path, "*.premis.xml")).select { |f| File.file?(f) }.each do |event_file|
  event_data = File.read(event_file)
  event_doc = Nokogiri::XML(event_data)
  source_identifier = event_doc.at_xpath("//premis:linkingObjectIdentifier[premis:linkingObjectRole='source']/premis:linkingObjectIdentifierValue")&.text
  outcome_identifier = event_doc.at_xpath("//premis:linkingObjectIdentifier[premis:linkingObjectRole='outcome']/premis:linkingObjectIdentifierValue")&.text
  unless source_identifier.nil? || source_identifier.empty?
    events_data_source[source_identifier] ||= []
    events_data_source[source_identifier] << event_file
  end
  unless outcome_identifier.nil? || outcome_identifier.empty?
    events_data_outcome[outcome_identifier] ||= []
    events_data_outcome[outcome_identifier] << event_file
  end
end

package_resources = Dir.glob(File.join(data_path, "**", "core.dor.json")).select { |f| File.file?(f) }
package_identifiers = []
package_resources.each do |core_path|
  STDERR.puts "### #{core_path}"
  resource_path = File.dirname(core_path)
  header_files = Dir.glob(File.join(resource_path, ".dor", "*")).select { |f| File.file?(f) }
  core_data = JSON.parse(File.read(File.join(resource_path, ".dor", "core.dor.json.json")), object_class: OpenStruct)
  soup_index = {}
  structure_path = nil
  header_files.each do |header_file|
    header_data = JSON.parse(File.read(header_file), object_class: OpenStruct)
    content_path = header_data.contentPath
    resource_file = File.join(resource_path, content_path)
    if content_path == "structure.dor.xml"
      structure_path = resource_file
    end
    unless File.exist?(resource_file)
      puts "- missing #{content_path} : #{header_file}"
      next
    end
    expected_resource_id = if content_path == "core.dor.json"
                             core_data.id
                           else
                             File.join(core_data.id, content_path)
                           end
    if header_data.id != expected_resource_id
      puts "- id mismatch #{header_data.id} != #{expected_resource_id} : #{header_file}"
    end

    if header_data.interactionModel.include?(":file:") || header_data.interactionModel.include?(":metadata:")
      if header_data.filename.nil? || header_data.filename.empty?
        puts "- missing filename : #{header_file}"
      end
      if header_data.function.nil? || header_data.function.empty?
        puts "- missing function : #{header_file}"
      end
    end

    if header_data.interactionModel.include?(":soup")
      soup_data = JSON.parse(File.read(resource_file))
      soup_data.keys.each do |key|
        soup_index[key] = true
      end
    end

    package_identifiers << header_data.id
  end
  # STDERR.puts soup_index.keys.join("\n")
  unless structure_path.nil?
    structure_doc = Nokogiri::XML(File.read(structure_path))
    structure_doc.xpath("//mets:div[@MDID]").each do |div_el|
      unless soup_index.keys.include?(div_el['MDID'])
        puts "- missing soup index for #{div_el['MDID']} : #{structure_path}"
      end
    end
  end
end

events_data_source.each do |source_id, event_files|
  unless package_identifiers.include?(source_id)
    puts "- event source #{source_id} not found"
    next
  end
end
events_data_outcome.each do |outcome_id, event_files|
  unless package_identifiers.include?(outcome_id)
    puts "- event outcome #{outcome_id} not found"
    next
  end
end
