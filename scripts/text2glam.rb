#!/usr/bin/env ruby

require 'sequel'
require 'inifile'
require 'optparse'
require 'ostruct'
require 'nokogiri'
require 'json'

require_relative '../lib/dor'
require_relative '../lib/dor/headers'
require_relative "../lib/xpat"
require_relative "../lib/dlxs"
require_relative "../lib/dlxs/utils"
require_relative "../lib/dlps_utils"
require 'pp'

HOST_NAME = "tang.umdl.umich.edu"
XPAT_HOST_NAME = "quod-update.umdl.umich.edu"
XPAT_EXEC = "/l/local/bin/xpatu"
XPAT_PORT = 620

config = IniFile.load("#{ENV['DLXSROOT']}/bin/i/image/etc/package.conf")
$db = Sequel.connect(:adapter=>'mysql2', :host=>config['mysql']['host'], :database=>config['mysql']['database'], :user=>config['mysql']['user'], :password=>config['mysql']['password'], :encoding => 'utf8mb4')
$db.extension :select_remove

$include_system_identifiers = false
$include_updated_by = false


def get_idnos_for_serial_issue(collection)
  STDERR.puts "not implemented"; exit;
  query = "pr.region.id region id"
  error, response = xpat.get_simple_results_from_query(query)
  result = DlpsUtils::twigify(response)
  doc = Nokogiri::XML(result) { |config| config.default_xml.noblanks }
  idnos = []
  doc.xpath("//IDNO").each do |idno_el|
    idnos << idno_el.content
  end
  idnos
end

def get_idnos_for_monograph(collection)
  query = "pr.region.id region id"
  idnos = []
  collection.dd_path.each do |dd_path|
    xpat = get_xpat(dd_path)
    error, response = xpat.get_simple_results_from_query(query)
    response.scan(%r{<IDNO[^>]*>(.*?)</IDNO>}m) do |match|
      idno = match.first.downcase
      idnos << [idno, xpat]
    end
  end
  idnos
end

def find_itemheader(idno, xpat)
  query = %(pr.region."mainheader" (region "mainheader" within (region main incl (region id incl ("#{idno} " + "#{idno}<"))));)
  error, response = xpat.get_simple_results_from_query(query)
  response
end

def get_xpat(dd_path)
  XPat.new(
    HOST_NAME,
    XPAT_HOST_NAME,
    dd_path,
    XPAT_EXEC,
    XPAT_PORT,
    200
  )
end

$_template_paths_cache = nil
def get_template_paths(collection)
  if $_template_paths_cache.nil?
    $_template_paths_cache = [ "#{ENV['DLXSROOT']}/web/digital-collections-style-guide/templates/text" ]
    if collection.config[:customfallbackwebdirs]
      collection.config[:customfallbackwebdirs].split("|").each do |dir|
        $_template_paths_cache << "#{ENV['DLXSROOT']}/web/#{dir}"
      end
    end
    $_template_paths_cache << "#{ENV['DLXSROOT']}/web/#{collection.config[:webdir]}"
  end
  $_template_paths_cache
end

def build_virtual_stylesheet(collection)  
  style_doc = File.open("/l1/dev/roger/bin/t/text/qui4metadata.xsl") { |f| Nokogiri::XML(f) }
  anchor_el = style_doc.xpath("//xsl:output").first
  fragment = Nokogiri::XML::DocumentFragment.new(style_doc)
  [
    "qui/qui.base.xsl", 
    "../vendor/str.split.function.xsl", 
    "../vendor/xslfunctions.xsl", 
    "qui/components/qui.language.xsl",
    "qui/includes/qui.header-common.xsl", 
    "qui/includes/qui.header-toc.xsl"].each do |template|
    get_template_paths(collection).each do |template_path|
      template_filename = File.join(template_path, template)
      if File.exist?(template_filename)
        import_el = Nokogiri::XML::Element.new("xsl:import", style_doc)
        import_el["href"] = template_filename
        fragment.add_child(import_el)
      end
    end
  end
  anchor_el.before(fragment)
  Nokogiri::XSLT::Stylesheet.parse_stylesheet_doc(style_doc)
end

def get_rightsmap_doc(collection)
  File.open("#{ENV['DLXSROOT']}/web/t/text/rightsmap.en.xml") { |f| Nokogiri::XML(f) }
end

def get_langmap_doc(collection)
  langmap_xml = "<LangMap>"
  get_template_paths(collection).reverse.each do |template_path|
    langmap_filename = File.join(template_path, "langmap.xml")
    if File.exist?(langmap_filename)
      langmap_xml += File.read(langmap_filename)
      break
    end
  end
  langmap_xml += File.read("#{ENV['DLXSROOT']}/web/digital-collections-style-guide/templates/text/langmap.en.xml")
  langmap_xml += "</LangMap>"
  Nokogiri::XML(langmap_xml) { |config| config.default_xml.noblanks }
end

options = OpenStruct.new()
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
end.parse!

if options.partner.nil?
  options.partner = options.collid
end

Random.srand(1001)

collection = DLXS::Collection::TextClass.new(options.collid)
$updated_at = File.mtime("/quod/obj/#{collection.collid[0]}/#{collection.collid}/#{collection.collid}.xml").to_datetime.to_s

encodingtype = collection.config[:encodingtype]
idnos = encodingtype == 'serialissue' ?
  get_idnos_for_serial_issue(collection) :
  get_idnos_for_monograph(collection)

puts "∆ #{encodingtype} -> #{idnos.length}"

if options.idno
  idnos.select! do |idno|
    if idno.is_a?(Array)
      idno.first == options.idno
    else
      idno == options.idno
    end
  end
end

stylesheet = build_virtual_stylesheet(collection)
tei_stylesheet = Nokogiri::XSLT(File.open("etc/tei3to5.xsl"))
structmap_stylesheet = Nokogiri::XSLT(File.open("etc/tei2structure.xsl"))
rightsmap_doc = get_rightsmap_doc(collection)
langmap_doc = get_langmap_doc(collection)

idnos.each do |idno, xpat|
  bookmarkable_url = "https://quod.lib.umich.edu/#{collection.collid[0]}/#{collection.collid}/#{idno}"
  check = $db[:nameresolver].where(coll: collection.collid, id: idno).first
  unless check.nil?
    bookmarkable_url = "https://name.umdl.umich.edu/#{idno}"
  end
  response = find_itemheader(idno, xpat)
  response = DlpsUtils::twigify(response)
  doc = Nokogiri::XML(response) { |config| config.default_xml.noblanks }
  metadata_xml = <<XML
<Top>
  <TemplateName>metadata</TemplateName>
  <DlxsGlobals></DlxsGlobals>
  <Item>
    <DocEncodingType>#{encodingtype}</DocEncodingType>
    <BookmarkableUrl>#{bookmarkable_url}</BookmarkableUrl>
    <ItemHeader></ItemHeader>
  </Item>
</Top>
XML
  metadata_doc = Nokogiri::XML(metadata_xml) { |config| config.default_xml.noblanks }
  metadata_doc.root.add_child(rightsmap_doc.root)
  metadata_doc.xpath("//DlxsGlobals").first.add_child(langmap_doc.root)
  metadata_doc.xpath("//ItemHeader").first.add_child(doc.xpath("//HEADER").first)
  encoding_level = metadata_doc.xpath("//HEADER/ENCODINGDESC/EDITORIALDECL").first['N']

  # print metadata_doc.to_xml

  core_metadata = {}
  result_doc = stylesheet.transform(metadata_doc)
  result_doc.xpath("//metadata/field").each do |field_el|
    key = field_el["key"]
    next if ["xxuseguidelines", "bookmark"].include?(key)
    label = field_el["label"]
    core_metadata["dc.#{key}"] = []
    field_el.xpath(".//value").each do |value_el|
      value = value_el.content.strip
      core_metadata["dc.#{key}"] << value unless value.empty?
      puts "#{key} (#{label}): #{value}"
    end
  end

  rights_statement = core_metadata.delete("dc.useguidelines")&.first

  dlxs_url = "https://quod.lib.umich.edu/#{options.collid[0]}/#{options.collid}/#{idno}"
  alternate_id = []
  if dlxs_url != bookmarkable_url
    alternate_id << { type: "urn:umich:lib:dlxs:url", value: dlxs_url }
    alternate_id << { type: "urn:umich:lib:dlxs:nameresolver", value: bookmarkable_url }
  else
    alternate_id << { type: "urn:umich:lib:dlxs:dlxs", value: bookmarkable_url }
  end

  local_identifier = idno
  submission_path = File.join(options.output_path, DOR::calculate_uuid(local_identifier, $submission_uuid))
  if File.exist?(submission_path)
    FileUtils.rm_rf(submission_path)
  end
  data_path = File.join(submission_path, "data")
  events_path = File.join(submission_path, "events")
  STDERR.puts ":: exporting to #{submission_path}"
  FileUtils.mkdir_p(data_path)
  FileUtils.mkdir_p(events_path)
  File.open(File.join(submission_path, "dor-info.txt"), "w") do |f|
    f.puts "Root-Identifier: #{local_identifier}"
    f.puts "Resource-Type: #{DOR::URN("resource:glam")}"
    f.puts "Action: Commit"
    f.puts "Agent-Name: Barbara Jensen"
    f.puts "Agent-Address: mailto:bjensen@umich.edu"
    f.puts "Version-Message: Migrating #{local_identifier} from DLXS"
  end

  # textclass resources are just the idno
  resource = DOR::Resource.new("#{idno}")
  resource.setup!(data_path)
  resource.add_file(
    DOR::ResourceFile.new(
      id: resource.id,
      parent: nil,
      content_path: "core.dor.json",
      mime_type: "application/json",
      interaction_model: DOR::URN("resource:glam"),
      alternate_id: alternate_id,
      partner_id: "info:partner/#{options.partner}",
      content: JSON.pretty_generate(core_metadata),
      updated_at: $updated_at
    )
  )

  query = %(pr.region.main ( region main incl (region id incl ("#{idno} " + "#{idno}<")) ))
  error, result = xpat.get_simple_results_from_query(query)
  result = DlpsUtils::twigify(result)
  doc = Nokogiri::XML(result) { |config| config.default_xml.noblanks }

  ## alternatively you can get the PB and then query for the sequence
  ## pr.region."page" ((region page incl (region "PB-T" incl (region "A-SEQ" incl "00000001"))) within (region main incl (region id incl ("851644.0008.047 " + "851644.0008.047<"))));

  div_el = doc.xpath("//BODY/DIV1").first
  div_el.xpath(".//P").each_with_index do |p_el, index|
    pb_els = p_el.xpath(".//PB")
    puts "#{index} :: #{pb_els.length}"
    content = p_el.inner_text.strip
    pb_el = pb_els.first

    m_fn = pb_el["SEQ"]
    fileset_resource = DOR::Resource.new("#{resource.id}/#{m_fn}")

    STDERR.puts ":: fileset #{fileset_resource.id}"

    # generate an asset for the resource
    page = $db[:Pageview].where(idno: idno, seq: pb_el["SEQ"]).order(Sequel.desc(:bpp)).first

    pending_id = "info:pending/#{idno}/#{m_fn}"
    fileset_resource.setup!(data_path)
    fileset_resource.add_file(
      DOR::ResourceFile.new(
        id: fileset_resource.id,
        parent: resource.id,
        content_path: "core.dor.json",
        mime_type: "application/json",
        interaction_model: DOR::URN("resource:fileset"),
        alternate_id: [
          { type: DOR::URN("packaging", "fileset"), value: pending_id },
        ],
        partner_id: "info:partner/#{options.partner}",
        content: JSON.pretty_generate({
          "dc.identifier" => [ "#{idno}/#{m_fn}" ],
          "dc.title" => [ "#{pb_el['REF']} - #{pb_el['SEQ']}" ]
        }),
        updated_at: page[:loaded].to_datetime.to_s
      )
    )

    asset = $db[:TextClassAsset].where(idno: idno, basename: File.basename(page[:image], '.*'), use: "access", access: 1).first
    asset_path = DLXS::Utils::generate_obj(fileset_resource.resource_path, asset)

    fileset_resource.add_file(
      asset_file = DOR::ResourceFile.new(
        id: File.join(fileset_resource.id, asset_path),
        parent: fileset_resource.id,
        content_path: File.basename(asset_path),
        mime_type: asset[:mimetype],
        interaction_model: DOR::URN("file", "image"),
        updated_at: asset[:loaded].to_datetime.to_s,
        filename: File.basename(asset_path),
        function: [DOR::URN("function", "source")]
      )
    )

    asset_md_path = DLXS::Utils::generate_techmd(fileset_resource.resource_path, asset_path)

    fileset_resource.add_file(
      asset_md_file = DOR::ResourceFile.new(
        id: File.join(fileset_resource.id, asset_md_path),
        parent: fileset_resource.id,
        content_path: File.basename(asset_md_path),
        mime_type: "application/xml",
        interaction_model: DOR::URN("metadata", "mix"),
        updated_at: asset[:loaded].to_datetime.to_s,
        filename: File.basename(asset_md_path),
        function: [DOR::URN("function", "technical")]
      )
    )

    unless content && content.empty?
      plaintext_asset = {
        basename: page[:seq],
        content: content,
        producer: 'primeocr'
      }

      plaintext_path = DLXS::Utils::generate_plaintext(fileset_resource.resource_path, plaintext_asset)

      fileset_resource.add_file(
        text_file = DOR::ResourceFile.new(
          id: File.join(fileset_resource.id, plaintext_path),
          parent: fileset_resource.id,
          content_path: File.basename(plaintext_path),
          mime_type: "text/plain",
          interaction_model: DOR::URN("file", "text"),
          updated_at: asset[:loaded].to_datetime.to_s,
          filename: File.basename(plaintext_path),
          function: [DOR::URN("function", "derived")]
        )
      )

      plaintext_md_path = DLXS::Utils::generate_techmd(fileset_resource.resource_path, plaintext_path)

      fileset_resource.add_file(
        plaintext_md_file = DOR::ResourceFile.new(
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
  end

  # transform doc to TEIP5
  # Nokogiri::XSLT.quote_params({ "title" => "Aaron's List" })).to_xml
  File.open("/tmp/doc.xml" , "w") { |f| f.write(doc.to_xml) }
  result = tei_stylesheet.transform(doc, Nokogiri::XSLT.quote_params({ "idno" => idno }))
  resource.add_file(
    DOR::ResourceFile.new(
      id: File.join(resource.id, "#{idno}~md.tei.xml"),
      parent: resource.id,
      content_path: "#{idno}~md.tei.xml",
      mime_type: "application/xml",
      interaction_model: DOR::URN("metadata", "tei"),
      updated_at: $updated_at,
      content: result.to_xml
    )
  )
  

  # transform TEIP5 to structure.dor.xml
  structmap = structmap_stylesheet.transform(
    result, 
    Nokogiri::XSLT.quote_params({ "idno" => idno, "encodingtype" => encodingtype })
  )
  resource.add_file(
    DOR::ResourceFile.new(
      id: File.join(resource.id, "structure.dor.xml"),
      parent: resource.id,
      content_path: "structure.dor.xml",
      mime_type: "application/xml",
      interaction_model: DOR::URN("structure"),
      updated_at: $updated_at,
      content: structmap.to_xml
    )
  )

  # generate rights.dor.json
  unless rights_statement.nil?
    rights_md = {}
    rights_md["dc.rights"] = [rights_statement]
    resource.add_file(
      DOR::ResourceFile.new(
        id: File.join(resource.id, "rights.dor.json"),
        parent: resource.id,
        content_path: "rights.dor.json",
        mime_type: "application/json",
        interaction_model: DOR::URN("rights"),
        updated_at: $updated_at,
        content: JSON.pretty_generate(rights_md)
      )
    )
  end

end

# query = "pr.region.id region id"
# error, response = xpat.get_simple_results_from_query(query)
# result = DlpsUtils::twigify(response)

# doc = Nokogiri::XML(result) { |config| config.default_xml.noblanks }
# doc.xpath("//IDNO").each do |idno_el|
#   puts idno_el.content
# end

