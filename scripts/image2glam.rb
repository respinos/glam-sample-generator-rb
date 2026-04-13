#!/usr/bin/env ruby

require 'sequel'
require 'inifile'
require 'optparse'
require 'ostruct'
require 'fileutils'
require 'json'
require 'nanoid'
require 'pp'
require 'builder'
require 'nokogiri'
require 'open3'
require 'debug'
require 'tty-command'

require_relative '../lib/dor'
require_relative '../lib/dor/headers'
require_relative '../lib/dlxs'
require_relative '../lib/dlxs/utils'

config = IniFile.load("#{ENV['DLXSROOT']}/bin/i/image/etc/package.conf")
$db = Sequel.connect(:adapter=>'mysql2', :host=>config['mysql']['host'], :database=>config['mysql']['database'], :user=>config['mysql']['user'], :password=>config['mysql']['password'], :encoding => 'utf8mb4')
$db.extension :select_remove

$include_system_identifiers = false
$include_updated_by = false

options = OpenStruct.new()
options.output_path = "examples"

OptionParser.new do |opts|
  opts.on("-c", "--collid COLLID", "Collection ID") do |c|
    options.collid = c
  end
  opts.on("--m_id M_ID", "m_id") do |c|
    options.m_id = c
  end
  opts.on("--partner PARTNER", "partner") do |c|
    options.partner = c
  end
  opts.on("--output_path OUTPUT_PATH", "output path") do |c|
    options.output_path = c
  end
  opts.on("--debug", "debug mode") do |v|
    options.debug = v
  end
  opts.on("--system_identifiers", "include system identifiers in header") do |v|
    $include_system_identifiers = true
    $include_updated_by = true
  end
end.parse!

if options.partner.nil?
  options.partner = options.collid
end

Random.srand(1001)

collection = DLXS::Collection.new(options.collid)

data_table = collection.config[:data_table]
media_table = collection.config[:media_table]

# 2. fetch a realistic updated_at
table_metadata = $db.fetch("SELECT * FROM information_schema.tables WHERE table_schema = ? AND table_name = ?", 'dlxs', data_table).first
$updated_at = table_metadata[:UPDATE_TIME].to_datetime.to_s

# fetch the folio and sheet metadata
records = []
$db[data_table.to_sym]
  .join(media_table.to_sym, m_id: :ic_id)
  .select_remove(:dlxs_sha)
  .select_remove(:ic_all)
  .select_remove(:pk_id)
  .select_remove(:m_rand)
  .where(ic_id: options.m_id)
  .order(:istruct_x, :istruct_y)
  .all.each do |row|
  record = {}
  row.each do |k, v|
    record[k.downcase.to_sym] = v
  end
  record[:m_id].downcase!
  record[:m_iid].downcase!
  record[:m_fn].downcase! unless record[:m_fn].nil?
  records << DLXS::Record.new(record)
end

puts ":: #{collection.config[:collname]}"
local_identifier = "#{options.collid}.#{options.m_id}"
submission_path = File.join(options.output_path, DOR::calculate_uuid(local_identifier, $submission_uuid))
if File.exist?(submission_path)
  FileUtils.rm_rf(submission_path)
end
data_path = File.join(submission_path, "data")
STDERR.puts ":: exporting to #{submission_path}"
FileUtils.mkdir_p(data_path)
File.open(File.join(submission_path, "dor-info.txt"), "w") do |f|
  f.puts "Root-Identifier: #{local_identifier}"
  f.puts "Resource-Type: #{DOR::URN("resource:glam")}"
  f.puts "Action: Commit"
  f.puts "Agent-Name: Barbara Jensen"
  f.puts "Agent-Address: mailto:bjensen@umich.edu"
  f.puts "Version-Message: Migrating #{local_identifier} from DLXS"
end

resource = DOR::Resource.new("#{options.collid}.#{options.m_id}")
resource.setup!(data_path)
resource.add_file(
  DOR::ResourceFile.new(
    id: resource.id,
    parent: nil,
    content_path: "core.dor.json",
    mime_type: "application/json",
    interaction_model: DOR::URN("resource"),
    alternate_id: [
      { type: "urn:umich:lib:dlxs:url", value: "https://quod.lib.umich.edu/#{options.collid[0]}/#{options.collid}/#{options.m_id}/#{options.m_iid}" },
      { type: "urn:umich:lib:dlxs:nameresolver", value: "IC-#{options.collid.upcase}-X-#{records[0].m_id}]1" },
    ],
    partner_id: "info:partner/#{options.partner}",
    content: JSON.pretty_generate(records[0].service_metadata(collection.xcoll_map)),
    updated_at: $updated_at
  )
)

# identify which metadata fields are used in the m_iid metadata
resource_ignore_fields = [
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
  :dc_ri,
  :dlxs_ri,
  :dlxs_ma
]
admin_map = collection.admin_map
unless admin_map["ic_vi"].nil?
  admin_map["ic_vi"].each do |field, _|
    resource_ignore_fields << field.to_s
  end
end

# make the resource service metadata
source_md_id = "#{resource.id}~md.json"
service_md_id = "#{resource.id}~md.service.json"

resource.add_file(
  DOR::ResourceFile.new(
    id: File.join(resource.id, source_md_id),
    parent: resource.id,
    content_path: source_md_id,
    mime_type: "application/json",
    interaction_model: DOR::URN("metadata"),
    function: [DOR::URN("function", "source")],
    updated_at: $updated_at,
    content: JSON.pretty_generate(records[0].metadata.reject { |k, _| resource_ignore_fields.include?(k.to_s) || k.to_s.start_with?("istruct_") || k.to_s.start_with?("m_") })
  )
)

dc_fields = []
collection.xcoll_map.keys.each do |k|
  next unless k.start_with?("dc_")
  next if k == "dc_ri"
  dc_fields.concat(collection.xcoll_map[k].keys)
end

# is there service metadata for the resource? No.
struct_md_map = {}
records.each do |record|
  record_source_md_id = "#{resource.id}-#{record.m_iid}~md.json"
  metadata = {}
  record.metadata.each do |k, v|
    next if admin_map["ic_vi"].nil?
    next unless admin_map["ic_vi"].has_key?(k.to_s.downcase)
    next if v.nil? || (v.is_a?(String) && v.empty?) || (v.is_a?(Array) && v.empty?)
    metadata[k] = v
  end
  resource.add_file(
    DOR::ResourceFile.new(
      id: File.join(resource.id, record_source_md_id),
      parent: resource.id,
      content_path: record_source_md_id,
      mime_type: "application/json",
      interaction_model: DOR::URN("metadata"),
      function:[ DOR::URN("function", "source")],
      updated_at: $updated_at,
      content: JSON.pretty_generate(metadata)
    )
  )

  record_service_md_id = "#{resource.id}-#{record.m_iid}~md.service.json"
  resource.add_file(
    DOR::ResourceFile.new(
      id: File.join(resource.id, record_service_md_id),
      parent: resource.id,
      content_path: record_service_md_id,
      mime_type: "application/json",
      interaction_model: DOR::URN("metadata"),
      function: [DOR::URN("function", "service")],
      updated_at: $updated_at,
      content: JSON.pretty_generate(record.service_metadata(collection.xcoll_map))
    )
  )

  unless record.m_fn.nil?
    struct_md_map[record.m_fn] = [source_md_id]
    struct_md_map[record.m_fn] << record_source_md_id
    struct_md_map[record.m_fn] << record_service_md_id
  end
end

# generate rights.dor.json
rights_data = {}
rights_statement = records[0].rights_statement(collection.xcoll_map)
resource.add_file(
  DOR::ResourceFile.new(
    id: File.join(resource.id, "rights.dor.json"),
    parent: resource.id,
    content_path: "rights.dor.json",
    mime_type: "application/json",
    interaction_model: DOR::URN("rights"),
    updated_at: $updated_at,
    content: JSON.pretty_generate({
      "dc.rights" => rights_statement
    })
  )
)

# generate structure.dor.xml
builder = Builder::XmlMarkup.new(:indent => 2)
builder.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
xml = builder.mets :structMap, "xmlns:mets" => "http://www.loc.gov/METS/v2" do |x|
  x.mets :div, :TYPE => "folio" do
    records.each_with_index do |record, idx|
      mdids = struct_md_map[record.m_fn].map { |mdid|  mdid }
      x.mets :div, :TYPE => "sheet", :ORDER => idx + 1, :ORDERLABEL => idx + 1, :MDID => mdids.join(" ") do      
        if record.has_media?
          x.mets :div, :TYPE => "canvas" do
            x.mets :mptr, :LOCTYPE => "URL", :LOCREF => "#{resource.id}/#{record.m_fn}"
          end
        end
      end
    end
  end
end
resource.add_file(
  DOR::ResourceFile.new(
    id: File.join(resource.id, "structure.dor.xml"),
    parent: resource.id,
    content_path: "structure.dor.xml",
    mime_type: "application/xml",
    interaction_model: DOR::URN("structure"),
    updated_at: $updated_at,
    content: xml
  )
)

DOR::Headers.update_resource_headers(resource.resource_path)

## NOW BUILD THE FILESET RESOURCES
records.each_with_index do |record, record_index|
  next unless record.has_media?
  fileset_resource = DOR::Resource.new("#{resource.id}/#{record.m_fn}")

  STDERR.puts ":: fileset #{fileset_resource.id}"

  fileset_resource.setup!(data_path)
  fileset_resource.add_file(
    DOR::ResourceFile.new(
      id: fileset_resource.id,
      parent: resource.id,
      content_path: "core.dor.json",
      mime_type: "application/json",
      interaction_model: DOR::URN("fileset"),
      alternate_id: [
        { type: DOR::URN("packaging", "fileset"), value: "info:pending/#{options.collid}/#{record.m_fn}" },
      ],
      partner_id: "info:partner/#{options.partner}",
      content: JSON.pretty_generate({
        "dc.identifier" => [ "#{options.collid}/#{record.m_fn}" ],
        "dc.title" => [ record.m_fn ]
      }),
      updated_at: $updated_at
    )
  )

  # generate an asset for the resource
  asset = $db[:ImageClassAsset].where(collid: options.collid, basename: record.m_fn, use: "access").first

  asset_path = DLXS::Utils::generate_asset(fileset_resource.resource_path, asset)

  fileset_resource.add_file(
    asset_file = DOR::ResourceFile.new(
      id: File.join(fileset_resource.id, asset_path),
      parent: fileset_resource.id,
      content_path: File.basename(asset_path),
      mime_type: "image/tiff",
      interaction_model: DOR::URN("file", "image"),
      updated_at: $updated_at,
      filename: File.basename(asset_path),
      function: [DOR::URN("function", "source")]
    )
  )

  asset_md_path = DLXS::Utils::generate_techmd(fileset_resource.resource_path, asset_path)

  fileset_resource.add_file(
    DOR::ResourceFile.new(
      id: File.join(fileset_resource.id, asset_md_path),
      parent: fileset_resource.id,
      content_path: File.basename(asset_md_path),
      mime_type: "application/xml",
      interaction_model: DOR::URN("metadata", "mix"),
      updated_at: $updated_at,
      filename: File.basename(asset_md_path),
      function: [DOR::URN("function", "technical")]
    )
  )

  plaintext_flds = admin_map["iiif_plaintext"]&.keys || []
  if options.collid == 'tinder'
    plaintext_flds = [ "fulltext#{record_index + 1}" ]
  end
  if record.has_plaintext?(plaintext_flds)

    # generate a plaintext file for the resource
    plaintext_asset = {
      basename: asset[:basename],
      content: record.plaintext(plaintext_flds),
      producer: 'zooniverse'
    }
    plaintext_path = DLXS::Utils::generate_plaintext(fileset_resource.resource_path, plaintext_asset)

    fileset_resource.add_file(
      DOR::ResourceFile.new(
        id: File.join(fileset_resource.id, plaintext_path),
        parent: fileset_resource.id,
        content_path: File.basename(plaintext_path),
        mime_type: "text/plain",
        interaction_model: DOR::URN("file", "plaintext"),
        updated_at: $updated_at,
        filename: File.basename(plaintext_path),
        function: [DOR::URN("function", "service"), DOR::URN("function", "source")]
      )
    )

    plaintext_md_path = DLXS::Utils::generate_techmd(fileset_resource.resource_path, plaintext_path)

    fileset_resource.add_file(
      DOR::ResourceFile.new(
        id: File.join(fileset_resource.id, plaintext_md_path),
        parent: fileset_resource.id,
        content_path: File.basename(plaintext_md_path),
        mime_type: "application/xml",
        interaction_model: DOR::URN("metadata", "textmd"),
        updated_at: $updated_at,
        filename: File.basename(plaintext_md_path),
        function: [DOR::URN("function", "technical")]
      )
    )
  end

  DOR::Headers.update_resource_headers(fileset_resource.resource_path)
end

puts "-30-"
