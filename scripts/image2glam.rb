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

Random.srand(1001)

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
options.headers_mode = "root"

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
  opts.on("--mode MODE", "headers mode") do |c|
    options.headers_mode = c
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

def write_description(filename, description)
  description_path = "#{filename}~desc.json"
  File.open(File.join(@resource_path, description_path), "w") do |f|
    f.write(JSON.pretty_generate(description))
  end
  @header_metadata[description_path] = {"interactionModel" => "urn:glam:use", "mimeType" => "application/use+json"}
  description_path
end

# 1x1 Black Pixel TIFF Generator (Dependency-Free)
def generate_black_tiff(filename = "black_1x1.tif")
  # Header: Little Endian (II), Version (42), Offset to first IFD (8)
  header = ["II", 42, 8].pack("A2vV")

  # IFD: Number of directory entries (9 tags for a basic valid TIFF)
  ifd_entries = 9
  
  # Tags: [Tag ID, Type, Count, Value/Offset]
  # Types: 3 = Short (16-bit), 4 = Long (32-bit)
  tags = [
    [0x0100, 3, 1, 1],      # ImageWidth: 1
    [0x0101, 3, 1, 1],      # ImageLength: 1
    [0x0102, 3, 1, 1],      # BitsPerSample: 1
    [0x0103, 3, 1, 1],      # Compression: 1 (No compression)
    [0x0106, 3, 1, 1],      # PhotometricInterpretation: 1 (Black is Zero)
    [0x0111, 4, 1, 122],    # StripOffsets: Pointer to pixel data (Header + IFD + NextOffset = 122)
    [0x0115, 3, 1, 1],      # SamplesPerPixel: 1
    [0x0116, 4, 1, 1],      # RowsPerStrip: 1
    [0x0117, 4, 1, 1]       # StripByteCounts: 1 byte
  ]

  # Pack the IFD
  ifd_data = [ifd_entries].pack("v")
  tags.each { |t| ifd_data << t.pack("vvVV") }
  ifd_data << [0].pack("V") # Next IFD Offset (0 = End of chain)

  # Pixel Data: 1 byte containing 1 bit of '0' (Black) padded with 0s
  pixel_data = [0b00000000].pack("C")

  File.open(filename, "wb") do |f|
    f.write(header)
    f.write(ifd_data)
    f.write(pixel_data)
  end
end

collection = db.fetch("SELECT * FROM ImageClass a JOIN Collection b ON a.collid = b.collid AND a.userid = b.userid WHERE a.collid = ? AND a.userid = 'dlxsadm'", options.collid).first
admin_map = _field2map(collection[:field_admin_maps])
xcoll_map = _field2map(collection[:field_xcoll_maps])
if xcoll_map["dc_ri"].nil? and ! xcoll_map["dlxs_ri"].nil?
  xcoll_map["dc_ri"] = xcoll_map["dlxs_ri"]
end
data_table = collection[:data_table]
media_table = collection[:media_table]

table_metadata = db.fetch("SELECT * FROM information_schema.tables WHERE table_schema = ? AND table_name = ?", 'dlxs', data_table).first
updated_at = table_metadata[:UPDATE_TIME]
record = {}
row = db[data_table.to_sym].select_remove(:dlxs_sha).where(ic_id: options.m_id).first
row.keys.each do |k|
  record[k.downcase.to_sym] = row[k]
end

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
local_identifier = "#{options.collid}.#{options.m_id}"
resource_path = "data/#{local_identifier}"
if File.exist?(resource_path)
  FileUtils.rm_rf(resource_path)
end
FileUtils.mkdir_p("data/#{local_identifier}/.dor")
@resource_path = resource_path
system_path = "#{resource_path}/.dor"
source_md_path = "#{local_identifier}-#{nanoid()}~md.json"
core_path = "core.json"

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

@header_metadata = {}
generated_files = []
File.open(File.join(resource_path, source_md_path), "w") do |f|
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
    if admin_map["iiif_plaintext"].include?(k.to_s)
      next
    end
    datum[k] = v.is_a?(String) ? v.split('|||') : v
  end
  f.write(JSON.pretty_generate(datum))
end
generated_files << source_md_path
@header_metadata[source_md_path] = {"interactionModel" => "urn:glam:metadata:#{options.collid}", "mimeType" => "application/glam+json"}
generated_files << write_description(source_md_path, {"use" => ["function:source",]})

record_mdref_map = {}
records.each do |record|
  record_mdref_map[record[:m_iid]] = []
end
records.each do |record|
  vi_md_path = "#{local_identifier}.#{record[:m_iid]}-#{nanoid()}~md.json"
  record_mdref_map[record[:m_iid]] << vi_md_path
  File.open(File.join(resource_path, vi_md_path), "w") do |f|
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
  generated_files << vi_md_path
  @header_metadata[vi_md_path] = {"interactionModel" => "urn:glam:metadata:#{options.collid}", "mimeType" => "application/glam+json"}
  generated_files << write_description(vi_md_path, {"use" => ["function:source"]})
end

File.open(File.join(resource_path, core_path), "w") do |f|
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
    "id": local_identifier,
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
    datum[:metadata][dc_k] = [value] unless value.empty?
  end
  f.write(JSON.pretty_generate(datum))
end
generated_files << core_path
@header_metadata[core_path] = {"interactionModel" => "urn:glam:metadata:service", "mimeType" => "application/dc+json"}

records.each do |record|
  vi_md_path = "#{local_identifier}.#{record[:m_iid]}-#{nanoid()}~md.json"
  record_mdref_map[record[:m_iid]] << vi_md_path
  File.open(File.join(resource_path, vi_md_path), "w") do |f|
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
  generated_files << vi_md_path
  @header_metadata[vi_md_path] = {"interactionModel" => "urn:glam:metadata:service", "mimeType" => "application/dc+json"}
  generated_files << write_description(vi_md_path, {"use" => ["function:service"]})
end


builder = Builder::XmlMarkup.new(:indent => 2)
builder.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
xml = builder.mets :structMap, "xmlns:mets" => "http://www.loc.gov/METS/v2" do |x|
  x.mets :div, :TYPE => "folio" do
    records.each_with_index do |record, idx|
      x.mets :div, :TYPE => "sheet", :ORDER => idx + 1, :ORDERLABEL => idx + 1, :MDID => "#{source_md_path} #{record_mdref_map[record[:m_iid]].join(" ")}" do      
        if record[:istruct_ms] == "P"
          x.mets :div, :TYPE => "canvas" do
            x.mets :mptr, :LOCATION => "#{local_identifier}/#{record[:m_fn]}"
          end
        end
      end
    end
  end
end
File.open(File.join(resource_path, "structure.xml"), "w") do |f|
  f.write(xml)
end
generated_files << "structure.xml"
@header_metadata["structure.xml"] = {"interactionModel" => "urn:glam:mets", "mimeType" => "application/mets+xml"}

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
    FileUtils.mkdir_p(File.join(resource_path, fileset_identifier))
    if options.headers_mode == 'resource'
      FileUtils.mkdir_p(File.join(resource_path, fileset_identifier, '.dor'))
      STDERR.puts ":: created #{File.join(resource_path, fileset_identifier, '.dor')}"
    else
      FileUtils.mkdir_p(File.join(system_path, fileset_identifier))
    end
    # 1. make fileset_identifier/core.json
    File.open(File.join(resource_path, fileset_identifier, "core.json"), "w") do |f|
      JSON.pretty_generate({})
    end
    generated_files << File.join(fileset_identifier, "core.json")
    @header_metadata[File.join(fileset_identifier, "core.json")] = {"interactionModel" => "urn:glam:metadata:service", "mimeType" => "application/dc+json"}

    # 2. make fileset_identifier/m_fn.tif
    generate_black_tiff(File.join(resource_path, fileset_identifier, "#{record[:m_fn]}.tif"))
    generated_files << File.join(fileset_identifier, "#{record[:m_fn]}.tif")
    @header_metadata[File.join(fileset_identifier, "#{record[:m_fn]}.tif")] = {"interactionModel" => "urn:glam:file", "mimeType" => "image/tiff"}

    # 3. make fileset_identifier/m_fn.tif~desc.json
    generated_files << write_description(File.join(fileset_identifier, "#{record[:m_fn]}.tif"), {"use" => ["function:source", "format:image"]})

    # 4. make fileset_identifier/m_fn.tif-NNNN~md.mix.xml
    mix_filename = "#{record[:m_fn]}.tif~md.mix.xml"
    doc = File.open(file_mets_xml) { |f| 
      Nokogiri::XML(f) { |config| config.default_xml.noblanks }
    }
    mix_el = doc.at_xpath("//mix:mix")
    File.open(File.join(resource_path, fileset_identifier, mix_filename), "w") do |f|
      f.write(mix_el.to_xml(indent: 2, encoding: 'UTF-8'))
    end
    @header_metadata[File.join(fileset_identifier, mix_filename)] = {"interactionModel" => "urn:glam:metadata", "mimeType" => "application/xml"}
    generated_files << File.join(fileset_identifier, mix_filename)
    # 5. make fileset_identifier/m_fn.tif-NNNN~md.mix.xml~desc.json
    generated_files << write_description(File.join(fileset_identifier, mix_filename), {"use" => ["function:technical"]})

    next if admin_map["iiif_plaintext"].nil?
    plaintext_flds = []
    if options.collid == 'tinder'
      # hand weaving
      key = "fulltext#{record_index + 1}"
      plaintext_flds << key
    end
    text_filename = "#{record[:m_fn]}.zooniverse.txt"
    File.open(File.join(resource_path, fileset_identifier, text_filename), "w") do |f|
      values = []
      plaintext_flds.each do |fld|
        value = record[fld.to_sym]
        values << value.split('|||') unless ( value.nil? || (value.is_a?(String) && value.empty?) )
      end
      values.flatten!
      f.write(values.join("\n"))
    end
    if File.size(File.join(resource_path, fileset_identifier, text_filename)) == 0
      FileUtils.rm(File.join(resource_path, fileset_identifier, text_filename))
      next
    end
    generated_files << File.join(fileset_identifier, text_filename)
    @header_metadata[File.join(fileset_identifier, text_filename)] = {"interactionModel" => "urn:glam:file", "mimeType" => "text/plain"}
    generated_files << write_description(File.join(fileset_identifier, text_filename), {"use" => ["function:source", "format:text-plain"]})

    
    `jhove -c etc/jhove.conf -h xml -m UTF8-hul #{File.join(resource_path, fileset_identifier, text_filename)} > #{File.join(resource_path, fileset_identifier, "#{text_filename}~md.textmd.xml")}`
    @header_metadata[File.join(fileset_identifier, "#{text_filename}~md.textmd.xml")] = {"interactionModel" => "urn:glam:file", "mimeType" => "application/textmd+xml"}
  end
end

generated_files.each do |filename|
  STDERR.puts ":: processing #{filename}"
  output_filename = File.join(system_path, "#{filename}.json")
  if filename.include?("/")
    output_filename = File.join(
      resource_path,
      File.dirname(filename),
      ".dor",
      "#{File.basename(filename)}.json"
    )
  end
  File.open(output_filename, "w") do |f|
    datum = {}
    datum["id"] = "info:root/#{local_identifier}/#{filename}"
    datum["parent"] = "info:root/#{local_identifier}"
    datum["interactionModel"] = @header_metadata[filename]['interactionModel']
    datum["contentSize"] = File.size(File.join(resource_path, filename))
    datum["mimeType"] = @header_metadata[filename]['mimeType']
    datum["filename"] = filename
    datum["digests"] = ["urn:sha-512:#{calculate_sha512(File.join(resource_path, filename))}"]
    datum["lastModifiedDate"] = updated_at.iso8601
    datum["lastModifiedBy"] = "dlxsadm"
    datum["deleted"] = false
    datum["visibility"] = "public"
    datum["contentPath"] = filename
    datum["headersVersion"] = "1.0.draft"

    f.write(JSON.pretty_generate(datum))
  end
end


puts "-30-"