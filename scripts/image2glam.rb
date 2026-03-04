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
  description_path
end

collection = db.fetch("SELECT * FROM ImageClass a JOIN Collection b ON a.collid = b.collid AND a.userid = b.userid WHERE a.collid = ? AND a.userid = 'dlxsadm'", options.collid).first
admin_map = _field2map(collection[:field_admin_maps])
xcoll_map = _field2map(collection[:field_xcoll_maps])
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
  records << record
end

# make the record path
FileUtils.mkdir_p("data/#{options.collid}.#{options.m_id}/.dor")
resource_path = "data/#{options.collid}.#{options.m_id}"
@resource_path = resource_path
local_identifier = "#{options.collid}.#{options.m_id}"
system_path = "#{resource_path}/.dor"
source_md_path = "#{local_identifier}-#{Nanoid.generate(size: 6)}~md.json"
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
    datum[k] = v.is_a?(String) ? v.split('|||') : v
  end
  f.write(JSON.pretty_generate(datum))
end
generated_files << source_md_path
generated_files << write_description(source_md_path, {"use" => ["function:source",]})

record_mdref_map = {}
records.each do |record|
  record_mdref_map[record[:m_iid]] = []
end
records.each do |record|
  vi_md_path = "#{local_identifier}.#{record[:m_iid]}-#{Nanoid.generate(size: 6)}~md.json"
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
  generated_files << write_description(vi_md_path, {"use" => ["function:source"]})
end

File.open(File.join(resource_path, core_path), "w") do |f|
  datum = {
    "id": local_identifier,
    "stakeholderId": options.collid,
    "rightsStatement": xcoll_map["dc_ri"]["_"][1..-2],
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

records.each do |record|
  vi_md_path = "#{local_identifier}.#{record[:m_iid]}-#{Nanoid.generate(size: 6)}~md.json"
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

    # record.each do |k, v|
    #   next if SKIP_FIELDS.include?(k)
    #   # next if v.nil?
    #   next if v.is_a?(String) && v.empty?
    #   next unless k.start_with?("istruct_") || k.start_with?("m_")
    #   datum[k] = v.is_a?(String) ? v.split('|||') : v
    # end
    f.write(JSON.pretty_generate(datum))
  end
  generated_files << vi_md_path
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
File.open(File.join(resource_path, "structmap.xml"), "w") do |f|
  f.write(xml)
end
generated_files << "structmap.xml"

generated_files.each do |filename|
  File.open(File.join(system_path, "#{filename}.json"), "w") do |f|
    datum = {}
    datum["id"] = "info:root/#{local_identifier}/#{filename}"
    datum["parent"] = "info:root/#{local_identifier}"
    datum["interactionModel"] = "urn:glam:metadata"
    datum["contentSize"] = File.size(File.join(resource_path, filename))
    datum["mimeType"] = "application/json"
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