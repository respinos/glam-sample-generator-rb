#!/usr/bin/env ruby

require 'sequel'
require 'inifile'
require 'optparse'
require 'ostruct'
require 'nokogiri'
require 'json'
require 'http'

require_relative '../lib/dor'
require_relative '../lib/dor/headers'
require_relative "../lib/dlxs"
require_relative "../lib/dlxs/utils"
require_relative "../lib/dlps_utils"
require 'pp'

DLXS_HOST = "quod.lib.umich.edu"
XPATH_FN_NS = "http://www.w3.org/2005/xpath-functions"
QUI_NS = "http://dlxs.org/quombat/ui"
TEI_NS = "http://www.tei-c.org/ns/1.0"
NSMAP = {
  'fn' => XPATH_FN_NS,
  'qui' => QUI_NS,
  'tei' => TEI_NS
}

config = IniFile.load("#{ENV['DLXSROOT']}/bin/i/image/etc/package.conf")
$db = Sequel.connect(:adapter=>'mysql2', :host=>config['mysql']['host'], :database=>config['mysql']['database'], :user=>config['mysql']['user'], :password=>config['mysql']['password'], :encoding => 'utf8mb4')
$db.extension :select_remove

$include_system_identifiers = false
$include_updated_by = false

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

collid = options.collid
idno = options.idno

tei_stylesheet = Nokogiri::XSLT(File.open("etc/tei3to5.xsl"))
structmap_stylesheet = Nokogiri::XSLT(File.open("etc/tei2structure.xsl"))

text_api_url = "https://#{DLXS_HOST}/cgi/t/text/text-idx?cc=#{collid}&idno=#{idno}"
pageviewer_api_url = "https://#{DLXS_HOST}/cgi/t/text/pageviewer-idx?cc=#{collid}&idno=#{idno}"
iiif_api_url = "https://#{DLXS_HOST}/cgi/t/text/api/manifest/#{collid}:#{idno}"
$updated_at = Time.now.to_datetime.to_s

local_identifier = options.idno
dlxs_url = "https://quod.lib.umich.edu/#{options.collid[0]}/#{options.collid}/#{idno}"
tei_filename = "#{idno}~md.tei.xml"
tei_fn = []

class Cache
  require 'pstore'
  CACHE_PATH = File.join("tmp", "cache")
  BASE_URI = "https://quod.lib.umich.edu/cgi/t/text"

  def initialize(collid)
    @session = HTTP.base_uri(BASE_URI).persistent
    @cache = PStore.new(File.join(CACHE_PATH, "#{collid}.pstore"))
    yield self if block_given?
  end

  def get(path)
    response = @cache.transaction(true) do
      if @cache.key?(path) and ! @cache[path].empty?
        STDERR.puts "::: #{path}"
        @cache[path]
      else
        nil
      end
    end
    return response unless response.nil?

    response = @cache.transaction do
      response = @session.get(path)
      STDERR.puts "<-- #{path}"
      # pp response.headers.to_h
      response = response.to_s
      @cache[path] = response
    end
    response
  end

end

# Cache.new options.collid do |cache|
#   local_identifier = options.idno
#   toc_xml = cache.get("text-idx?cc=#{collid}&idno=#{idno}&view=toc&debug=qui").to_s
#   toc_doc = Nokogiri::XML(toc_xml)  { |config| config.default_xml.noblanks }
# end
# exit


Cache.new options.collid do |cache|
  local_identifier = options.idno
  toc_xml = cache.get("text-idx?cc=#{collid}&idno=#{idno}&view=toc&debug=qui").to_s
  toc_doc = Nokogiri::XML(toc_xml)  { |config| config.default_xml.noblanks }

  core_md = {}
  toc_doc.xpath('//qui:metadata/qui:field').each do |field_el|
    key = "dc.#{field_el['key']}"
    core_md[key] = []
    field_el.xpath('.//qui:value').each do |value_el|
      core_md[key] << value_el.text
    end
  end

  encodingtype = toc_doc.xpath("//qui:metadata[@slot='root']/@encoding-type")

  bookmarkable_url = core_md.delete('dc.bookmark')&.first
  rights_statement = core_md.delete("dc.useguidelines")&.first
  core_md.delete("dc.citation")

  alternate_id = []
  if ! bookmarkable_url.nil? && bookmarkable_url != dlxs_url
    alternate_id << { type: "urn:umich:lib:dlxs:url", value: dlxs_url }
    alternate_id << { type: "urn:umich:lib:dlxs:nameresolver", value: bookmarkable_url }
  else
    alternate_id << { type: "urn:umich:lib:dlxs:url", value: dlxs_url }
  end

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
      content: JSON.pretty_generate(core_md),
      updated_at: $updated_at
    )
  )

  has_images = toc_doc.xpath("//qui:block[@slot='contents']//qui:link[contains(@href, 'pageviewer-idx')]").any?
  if has_images
    # manifest_json = cache.get("api/manifest/#{collid}:#{idno}").to_s
    # manifest = JSON.parse(manifest_json)

    # manifest['sequences'].each do |sequence|
    #   sequence['canvases'].each do |canvas|
    #     image_resource = canvas['images'].first['resource']
    #     image_id = image_resource['service']['@id']

    #     m_fn = image_id.split(":").last
    #     fileset_resource = DOR::Resource.new("#{resource.id}/#{m_fn}")
        
    #     image_data = cache.get("#{image_id}/full/250,/0/native.tif")
    #     resource.add_file(
    #       DOR::ResourceFile.new(
    #         id: File.join(resource.id, m_fn),
    #         parent: resource.id,
    #         content_path: "#{m_fn}.tif",
    #         mime_type: "image/tiff",
    #         interaction_model: DOR::URN("file:image"),
    #         content: image_data,
    #         updated_at: $updated_at
    #       )
    #     )
    #   end
    # end

    pageviewer_link = toc_doc.xpath("//qui:block[@slot='contents']//qui:link[contains(@href, 'pageviewer-idx')]").first
    pageviewer_href = CGI.unescape(pageviewer_link['href'].split('/cgi/t/text/').last)
    pageviewer_xml = cache.get(pageviewer_href).to_s
    pageviewer_doc = Nokogiri::XML(pageviewer_xml)  { |config| config.default_xml.noblanks }
    pageviewer_doc.xpath('//qui:viewer/fn:map//fn:array[@key="sequences"]/fn:map/fn:array[@key="canvases"]/fn:map', **NSMAP).each do |canvas_el|
      image_id = canvas_el.xpath('.//fn:array[@key="images"]/fn:map/fn:map[@key="resource"]/fn:map[@key="service"]/fn:string[@key="@id"]', **NSMAP).text
      pagetext_href = canvas_el.xpath('.//fn:map[@key="seeAlso"]/fn:string[@key="@id"]', **NSMAP).text
      pagetext_href = pagetext_href.split('/cgi/t/text/').last unless pagetext_href.empty?
      
      STDERR.puts image_id

      m_fn = image_id.split(":").last
      pending_id = "info:pending/#{idno}/#{m_fn}"

      fileset_resource = DOR::Resource.new("#{resource.id}/#{m_fn}")
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
            "dc.title" => [ m_fn ]
          }),
          updated_at: $updated_at
        )
      )
      
      image_data = cache.get("#{image_id}/full/250,/0/native.tif")
      asset_path = "#{m_fn}.tif"
      fileset_resource.add_file(
        asset_file = DOR::ResourceFile.new(
          id: File.join(resource.id, m_fn),
          parent: resource.id,
          content_path: "#{m_fn}.tif",
          mime_type: "image/tiff",
          interaction_model: DOR::URN("file:image"),
          content: image_data,
          updated_at: $updated_at
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
          updated_at: $updated_at,
          filename: File.basename(asset_md_path),
          function: [DOR::URN("function", "technical")]
        )
      )

      if !pagetext_href.nil? && !pagetext_href.empty?
        pagetext_xml = cache.get(pagetext_href + ";debug=qui")
        pagetext_doc = Nokogiri::XML(pagetext_xml)  { |config| config.default_xml.noblanks }
        content = pagetext_doc.xpath('//tei:ResultFragment/tei:P', **NSMAP).map(&:inner_text).join("\n\n").strip

        unless content.empty?
          plaintext_asset = {
            basename: m_fn,
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
              updated_at: $updated_at,
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

      # DOR::Headers.update_resource_headers(fileset_resource.resource_path)
    end
  else
    STDERR.puts "- #{idno}"
  end


  # transform DLXS TEI to TEIP5
  text_xml = cache.get("text-idx?cc=#{collid}&idno=#{idno}&debug=xml&view=text&_=xyzzy&rgn=main&rewrap=no").to_s
  text_doc = Nokogiri::XML(text_xml)  { |config| config.default_xml.noblanks }
  teip5_doc = tei_stylesheet.transform(text_doc, Nokogiri::XSLT.quote_params({ "idno" => idno, "encodingtype" => encodingtype }))
  resource.add_file(
    DOR::ResourceFile.new(
      id: File.join(resource.id, tei_filename),
      parent: resource.id,
      content_path: tei_filename,
      mime_type: "application/xml",
      interaction_model: DOR::URN("metadata", "tei"),
      function: tei_fn,
      updated_at: $updated_at,
      content: teip5_doc.to_xml
    )
  )

  teip5_doc.xpath("//tei:div1[tei:bibl]", **NSMAP).each do |div1_el|
    # extract the service metadata for each div1
    node_md = {}
    node_md["dc.identifier.section"] = [div1_el['glam:node']]
    node_md["dc.title.section"] = [div1_el.at_xpath("tei:bibl/tei:title", **NSMAP)&.text]
    citation = []
    [['vol', 'Volume'], ['iss', 'Issue']].each do |attr, label|
      bibl_el = div1_el.at_xpath("tei:bibl/tei:biblScope[@type='#{attr}']", **NSMAP)
      citation << "#{label} #{bibl_el.text}" if bibl_el
    end
    date = []
    [ 'mo', 'year' ].each do |attr|
      bibl_el = div1_el.at_xpath("tei:bibl/tei:biblScope[@type='#{attr}']", **NSMAP)
      date << bibl_el.text if bibl_el
    end
    citation << date.join(" ") unless date.empty?
    node_md["dcterms.bibliographicCitation"] = [citation.join(", ")]
    file_id = "#{File.join(resource.id, div1_el['glam:node'])}~md.service.json"
    service_filename = "#{div1_el['glam:node'].gsub(':', '-')}~md.service.json"
    resource.add_file(
      DOR::ResourceFile.new(
        id: file_id,
        parent: resource.id,
        content_path: service_filename,
        mime_type: "application/json",
        interaction_model: DOR::URN("metadata"),
        content: JSON.pretty_generate(node_md),
        updated_at: $updated_at
      )
    )
  end

  # transform TEIP5 to structure.dor.xml
  structmap = structmap_stylesheet.transform(
    teip5_doc,
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

  DOR::Headers.update_resource_headers(resource.resource_path)

end