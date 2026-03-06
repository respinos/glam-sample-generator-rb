#!/usr/bin/env ruby

require 'sequel'
require 'inifile'
require 'optparse'
require 'ostruct'
require 'fileutils'
require 'json'
require 'nanoid'
require 'digest'
require 'pp'
require 'builder'
require 'nokogiri'
require 'open3'
require 'debug'
require 'tty-command'
require 'uuid7'

ResourceFile = Struct.new(:filename, :use, :interactionModel, :mimeType, keyword_init: true) do
  attr_reader :system_identifier
  def initialize(*args)
    super(*args)
    @system_identifier = UUID7.generate
    # self.resource_path ||= $resource_path
    # self.system_path ||= $header_path
  end

  def resource_path
    File.join($resource_path, filename)
  end

  def header_path(rooted)
    if rooted
      File.join($header_path, "#{filename}.json")
    else
      File.join($resource_path, File.dirname(filename), ".dor", "#{File.basename(filename)}.json")
    end
  end
  
  def desc
    self.class.new(
      filename: "#{filename}~desc.json",
      use: use,
      interactionModel: "urn:glam:use",
      mimeType: "application/use+json"
    )
  end
end

Random.srand(1001)

cmd = TTY::Command.new(printer: :null)

DC_MAP = {}
DC_MAP["dc_ri"] = "dc.rights"
DC_MAP["dc_ti"] = "dc.title"
DC_MAP["dc_cr"] = "dc.creator"
DC_MAP["dc_su"] = "dc.subject"
DC_MAP["dc_de"] = "dc.description"
DC_MAP["dc_so"] = "dc.source"
DC_MAP["dc_fo"] = "dc.format"
DC_MAP["dc_da"] = "dc.date"
DC_MAP["dc_id"] = "dc.identifier"
DC_MAP["dc_rel"] = "dc.relation"
DC_MAP["dc_type"] = "dc.type"
DC_MAP["dc_la"] = "dc.language"
DC_MAP["dc_cov"] = "dc.coverage"
DC_MAP["dc_gen"] = "dc.genre"

config = IniFile.load("#{ENV['DLXSROOT']}/bin/i/image/etc/package.conf")
db = Sequel.connect(:adapter=>'mysql2', :host=>config['mysql']['host'], :database=>config['mysql']['database'], :user=>config['mysql']['user'], :password=>config['mysql']['password'], :encoding => 'utf8mb4')
db.extension :select_remove

options = OpenStruct.new()
options.rooted = true

OptionParser.new do |opts|
  opts.on("-c", "--collid COLLID", "Collection ID") do |c|
    options.collid = c
  end
  opts.on("--m_id M_ID", "m_id") do |c|
    options.m_id = c
  end
  opts.on("--m_iid M_IID", "m_iid") do |c|
    options.m_iid = c
  end
  opts.on("--[no-]rooted", "rooted mode") do |v|
    options.rooted = v
  end
end.parse!

def calculate_sha512(file_path)
  # Create a new SHA512 digest object
  sha512 = Digest::SHA512.new
  
  # Open the file in binary read mode ('rb') for cross-platform compatibility
  File.open(file_path, 'rb') do |file|
    # Read the file in chunks and update the digest object
    # The digest object can handle incremental updates
    buffer = ''
    while file.read(1024, buffer)
      sha512.update(buffer)
    end
  end
  
  # Return the final hexdigest (a 128-character hexadecimal string)
  sha512.hexdigest
end

def nanoid()
  Nanoid.generate(size: 6, non_secure: true)
end

def _field2map(s)
  mapping = {}
  if s.nil?
    return mapping
  end
  lines = s.split("|")
  lines.each do |line|
    if not line.empty?
      key, values = line.split(':::')
      key.downcase!
      mapping[key] = {}
      if values.nil?
        mapping[key][key] = 1
      elsif values[0] == '"'
        mapping[key]['_'] = values
      else
        values.split(' ').each do |value|
          mapping[key][value.downcase] = 1
        end
      end
    end
  end
  mapping
end

def write_description(desc)
  File.open(desc.resource_path, "w") do |f|
    f.write(JSON.pretty_generate({ use: desc.use }))
  end
  desc
end

# 1. fetch the collection configuration
collection = db.fetch("SELECT * FROM ImageClass a JOIN Collection b ON a.collid = b.collid AND a.userid = b.userid WHERE a.collid = ? AND a.userid = 'dlxsadm'", options.collid).first
admin_map = _field2map(collection[:field_admin_maps])
xcoll_map = _field2map(collection[:field_xcoll_maps])
if xcoll_map["dc_ri"].nil? and ! xcoll_map["dlxs_ri"].nil?
  xcoll_map["dc_ri"] = xcoll_map["dlxs_ri"]
end
if xcoll_map["dc_ti"].nil? and ! xcoll_map["dlxs_ma"].nil?
  xcoll_map["dc_ti"] = xcoll_map["dlxs_ma"]
end
data_table = collection[:data_table]
media_table = collection[:media_table]

# 2. fetch a realistic updated_at
table_metadata = db.fetch("SELECT * FROM information_schema.tables WHERE table_schema = ? AND table_name = ?", 'dlxs', data_table).first
$updated_at = table_metadata[:UPDATE_TIME]

# 3. fetch the folio metadata for the folio
record = {}
row = db[data_table.to_sym].select_remove(:dlxs_sha).where(ic_id: options.m_id).first
row.keys.each do |k|
  record[k.downcase.to_sym] = row[k]
end

# fetch the folio and sheet metadata
records = []
db[data_table.to_sym].join(media_table.to_sym, m_id: :ic_id).where(ic_id: options.m_id).order(:istruct_x, :istruct_y).all.each do |row|
  record = {}
  row.each do |k, v|
    record[k.downcase.to_sym] = v
  end
  record[:m_id].downcase!
  record[:m_iid].downcase!
  record[:m_fn].downcase! unless record[:m_fn].nil?
  records << record
end

# make the record path
$output_path = options.rooted ? "examples/rooted" : "examples/nested"
$local_identifier = "#{options.collid}.#{options.m_id}"
$resource_path = "#{$output_path}/#{$local_identifier}"
if File.exist?($resource_path)
  FileUtils.rm_rf($resource_path)
end
FileUtils.mkdir_p("#{$resource_path}/.dor")
$resource_path = $resource_path
$header_path = "#{$resource_path}/.dor"

SKIP_FIELDS = [
  :ic_id, 
  :ic_all, 
  :dlxs_sha, 
  :m_rand, 
  :istruct_isentryid, 
  :istruct_isentryidv, 
  :m_flm, 
  :m_fn,
  :istruct_m,
  :istruct_me,
  :istruct_mo,
  :istruct_ms,
  :istruct_mt,
  :istruct_stid,
  :istruct_stty,
  :istruct_x,
  :istruct_y,
  :istruct_caption,
  :m_caption,
]

# write the record metadata: skip the ic_vi and ic_fn fields

generated_files = []
source_md = ResourceFile.new(filename: "#{$local_identifier}~md.json", use: ["function:source"], interactionModel: "urn:glam:metadata:#{options.collid}", mimeType: "application/glam+json")
File.open(source_md.resource_path, "w") do |f|
  datum = {}
  record.each do |k, v|
    next if SKIP_FIELDS.include?(k)
    # next if v.nil?
    next if v.is_a?(String) && v.empty?
    if admin_map["ic_vi"].include?(k.to_s)
      next
    end
    if admin_map["ic_fn"].include?(k.to_s)
      next
    end
    if admin_map['iiif_plaintext'] && admin_map["iiif_plaintext"].include?(k.to_s)
      next
    end
    datum[k] = v.is_a?(String) ? v.split('|||') : v
  end
  f.write(JSON.pretty_generate(datum))
end
generated_files << source_md
generated_files << write_description(source_md.desc)

record_mdref_map = {}
records.each do |record|
  vi_md = ResourceFile.new(filename: "#{$local_identifier}.#{record[:m_iid]}-#{nanoid()}~md.json", use: ["function:source"], interactionModel: "urn:glam:metadata:#{options.collid}", mimeType: "application/glam+json")
  record_mdref_map[record[:m_iid]] ||= []
  record_mdref_map[record[:m_iid]] << vi_md
  File.open(vi_md.resource_path, "w") do |f|
    datum = {}
    record.each do |k, v|
      next if SKIP_FIELDS.include?(k)
      # next if v.nil?
      next if v.is_a?(String) && v.empty?
      next unless k.start_with?("istruct_") || k.start_with?("m_")
      datum[k] = v.is_a?(String) ? v.split('|||') : v
    end
    f.write(JSON.pretty_generate(datum))
  end  
  generated_files << vi_md
  generated_files << write_description(vi_md.desc)
end

core_md = ResourceFile.new(filename: "core.json", use: ["function:service"], interactionModel: "urn:glam:metadata:service", mimeType: "application/dc+json")
File.open(core_md.resource_path, "w") do |f|
  rights_statement = if xcoll_map["dc_ri"]["_"].nil?
    value = []
    xcoll_map["dc_ri"].keys.each do |fld|
      value << record[fld.to_sym] unless ( record[fld.to_sym].nil? )
    end
    value.join(' / ')
  else
    xcoll_map["dc_ri"]["_"][1..-2]
  end
  datum = {
    "id": $local_identifier,
    "stakeholderId": options.collid,
    "rightsStatement": rights_statement,
    "metadata": {}
  }
  xcoll_map.each do |k, v|
    next unless k.start_with?("dc_")
    next if k == "dc_ri"
    value = []
    v.each do |fld, _|
      value << record[fld.to_sym] unless ( record[fld.to_sym].nil? || (record[fld.to_sym].is_a?(String) && record[fld.to_sym].empty?) )
    end
    dc_k = DC_MAP[k]
    STDERR.puts "?? #{dc_k} :: #{k}"
    datum[:metadata][dc_k] = [value] unless value.empty?
  end
  f.write(JSON.pretty_generate(datum))
end
generated_files << core_md

records.each do |record|
  vi_md = ResourceFile.new(filename: "#{$local_identifier}.#{record[:m_iid]}-#{nanoid()}~md.json", use: ["function:service"], interactionModel: "urn:glam:metadata:#{options.collid}", mimeType: "application/dc+json")
  record_mdref_map[record[:m_iid]] << vi_md
  File.open(vi_md.resource_path, "w") do |f|
    datum = {}
    xcoll_map.each do |k, v|
      next unless k.start_with?("dc_")
      next if k == "dc_ri"
      value = []
      STDERR.puts "#{k} -> #{v.keys.join(' / ')}"
      if k == 'dc_ti'
        v.keys.each do |fld|
          STDERR.puts "== #{fld} :: #{record[fld.to_sym]}"
        end
      end
      v.each do |fld, _|
        value << record[fld.to_sym] unless ( record[fld.to_sym].nil? || (record[fld.to_sym].is_a?(String) && record[fld.to_sym].empty?) )
      end
      dc_k = DC_MAP[k]
      datum[dc_k] = [value] unless value.empty?
    end
    f.write(JSON.pretty_generate(datum))
  end
  generated_files << vi_md
  generated_files << write_description(vi_md.desc)
end

structure_file = ResourceFile.new(filename: "structure.xml", use: ["function:structure"], interactionModel: "urn:glam:mets", mimeType: "application/mets+xml")
builder = Builder::XmlMarkup.new(:indent => 2)
builder.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
xml = builder.mets :structMap, "xmlns:mets" => "http://www.loc.gov/METS/v2" do |x|
  x.mets :div, :TYPE => "folio" do
    records.each_with_index do |record, idx|
      mdids = [ "_" + source_md.system_identifier ]
      record_mdref_map[record[:m_iid]].each do |mdref|
        mdids << "_" + mdref.system_identifier
      end
      x.mets :div, :TYPE => "sheet", :ORDER => idx + 1, :ORDERLABEL => idx + 1, :MDID => mdids.join(" ") do      
        if record[:istruct_ms] == "P"
          x.mets :div, :TYPE => "canvas" do
            x.mets :mptr, :LOCATION => "#{$local_identifier}/#{record[:m_fn]}"
          end
        end
      end
    end
  end
end
File.open(structure_file.resource_path, "w") do |f|
  f.write(xml)
end
generated_files << structure_file

records.each_with_index do |record, record_index|
  puts "== WTF #{record[:m_id]} :: #{record[:istruct_ms]}"
  if record[:istruct_ms] == "P"
    asset = db[:ImageClassAsset].where(collid: options.collid, basename: record[:m_fn], use: "access").first
    asset_path = File.join("/quod/asset", asset[:filename])
    actual_asset_path = File.readlink(asset_path)
    file_mets_xml = File.join(
      "/quod/asset",
      File.dirname(asset[:filename]),
      actual_asset_path.gsub(".jp2", ".file.mets.xml")
    )

    fileset_identifier = asset[:basename].downcase
    image_file = ResourceFile.new(filename: "#{fileset_identifier}/#{record[:m_fn]}.tif", use: ["function:source", "format:image"], interactionModel: "urn:glam:file", mimeType: "image/tiff")
    core_md = ResourceFile.new(filename: "#{fileset_identifier}/core.json", use: ["function:service"], interactionModel: "urn:glam:metadata:service", mimeType: "application/dc+json")  

    FileUtils.mkdir_p(File.dirname(image_file.resource_path))
    FileUtils.mkdir_p(File.dirname(image_file.header_path(options.rooted)))
    # 1. make fileset_identifier/core.json
    File.open(core_md.resource_path, "w") do |f|
      JSON.pretty_generate({})
    end
    generated_files << core_md

    # 2. make fileset_identifier/m_fn.tif
    out, status = Open3.pipeline([
      'kdu_expand', 
      '-i', 
      asset_path,
      '-o',
      image_file.resource_path,
      '-reduce', asset[:levels].to_s
    ])

    generated_files << image_file

    # 3. make fileset_identifier/m_fn.tif~desc.json
    generated_files << write_description(image_file.desc)

    # 4. make fileset_identifier/m_fn.tif-NNNN~md.mix.xml
    mix_filename = "#{record[:m_fn]}.tif~md.mix.xml"
    mix_file = ResourceFile.new(filename: "#{fileset_identifier}/#{mix_filename}", use: ["function:technical"], interactionModel: "urn:glam:metadata", mimeType: "application/mix+xml")
    out, status = cmd.run(
      'jhove',
      '-c', 'etc/jhove.conf',
      '-h', 'xml',
      image_file.resource_path
    )

    doc = Nokogiri::XML(out.to_s) { |config| config.default_xml.noblanks }
    # jhove_mix_el = doc.at_xpath("//jhove:property[name='NisoImageMetadata']/jhove:values[@type='NISOImageMetadata']/jhove:value/node()", 'jhove' => 'http://hul.harvard.edu/ois/xml/ns/jhove')
    # jhove_mix_el = doc.at_xpath("//jhove:jhove", 'jhove' => 'http://hul.harvard.edu/ois/xml/ns/jhove')
    jhove_mix_el = doc.at_xpath('//mix:mix', 'mix' => 'http://www.loc.gov/mix/v20')
    File.open(mix_file.resource_path, "w") do |f|
      f.write(jhove_mix_el.to_xml(indent: 2, encoding: 'UTF-8'))
    end

    generated_files << mix_file
    # 5. make fileset_identifier/m_fn.tif-NNNN~md.mix.xml~desc.json
    generated_files << write_description(mix_file.desc)

    next if admin_map["iiif_plaintext"].nil?
    plaintext_flds = []
    if options.collid == 'tinder'
      # hand weaving
      key = "fulltext#{record_index + 1}"
      plaintext_flds << key
    end
    text_filename = "#{record[:m_fn]}.zooniverse.txt"
    text_file = ResourceFile.new(filename: "#{fileset_identifier}/#{text_filename}", use: ["function:source", "format:text-plain"], interactionModel: "urn:glam:file", mimeType: "text/plain")
    File.open(text_file.resource_path, "w") do |f|
      values = []
      plaintext_flds.each do |fld|
        value = record[fld.to_sym]
        values << value.split('|||') unless ( value.nil? || (value.is_a?(String) && value.empty?) )
      end
      values.flatten!
      f.write(values.join("\n"))
    end
    if File.size(text_file.resource_path) == 0
      FileUtils.rm(text_file.resource_path)
      next
    end
    generated_files << text_file
    generated_files << write_description(text_file.desc)

    text_md_file = ResourceFile.new(filename: "#{fileset_identifier}/#{text_filename}~md.textmd.xml", use: ["function:technical"], interactionModel: "urn:glam:metadata", mimeType: "application/textmd+xml")
    out, status = cmd.run(
      'jhove',
      '-c', 'etc/jhove.conf',
      '-h', 'xml',
      '-m', 'UTF8-hul',
      text_file.resource_path
    )
    doc = Nokogiri::XML(out.to_s) { |config| config.default_xml.noblanks }
    jhove_textmd_el = doc.at_xpath('//textmd:textMD', 'textmd' => 'info:lc/xmlns/textMD-v3')
    File.open(text_md_file.resource_path, "w") do |f|
      f.write(jhove_textmd_el.to_xml(indent: 2, encoding: 'UTF-8'))
    end
    generated_files << text_file
    generated_files << write_description(text_file.desc)
  end
end

generated_files.each do |resource_file|
  STDERR.puts ":: processing #{resource_file.filename}"
  output_filename = resource_file.header_path(options.rooted)
  File.open(output_filename, "w") do |f|
    datum = {}
    datum["id"] = "info:root/#{$local_identifier}/#{resource_file.filename}"
    datum["parent"] = "info:root/#{$local_identifier}"
    datum["interactionModel"] = resource_file.interactionModel
    datum["contentSize"] = File.size(resource_file.resource_path)
    datum["mimeType"] = resource_file.mimeType
    datum["filename"] = resource_file.filename
    datum["digests"] = ["urn:sha-512:#{calculate_sha512(resource_file.resource_path)}"]
    datum["lastModifiedDate"] = $updated_at.iso8601
    datum["lastModifiedBy"] = "dlxsadm"
    datum["deleted"] = false
    datum["visibility"] = "public"
    datum["contentPath"] = resource_file.filename
    datum["headersVersion"] = "1.0.draft"

    f.write(JSON.pretty_generate(datum))
  end
end


puts "-30-"