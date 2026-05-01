#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'fileutils'
require 'json'
require 'cgi'
require 'uri'
require 'http'
require 'pp'
require 'builder'
require 'nokogiri'
require 'debug'
require 'tty-command'

require_relative '../lib/dor'
require_relative '../lib/dor/headers'
require_relative '../lib/dlxs'
require_relative '../lib/dlxs/utils'
require_relative '../lib/cache'

# Register a custom function under a specific namespace URI
Nokogiri::XSLT.register("urn:umich:lib:dor:model:2026:resource:glam", Class.new do
  def hash_id(input)
    # The input from XSLT is often a NodeSet or an Array; 
    # we convert to string to hash it.
    str = input.is_a?(Enumerable) ? input.first.to_s : input.to_s
    DOR::to_xml_id(str.downcase)
  end

  def basename(input)
    str = input.is_a?(Enumerable) ? input.first.to_s : input.to_s
    File.basename(str, ".*").downcase
  end

  def from_url(input)
    str = input.is_a?(Enumerable) ? input.first.to_s : input.to_s
    tmp = str.split('/')
    tmp.pop # native.jpg
    tmp.pop # rotate
    tmp.pop # region
    tmp.pop #size
    identifier = File.basename(tmp.pop.downcase, ".*")
    identifier.split(":").last
  end

  def from_cgi(input)
    str = input.is_a?(Enumerable) ? input.first.to_s : input.to_s
    uri = URI.parse(str)
    params = CGI.parse(uri.query)
    File.basename(params["viewid"].first.downcase, ".*")
  end
end)

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

XPATH_FN_NS = "http://www.w3.org/2005/xpath-functions"
QUI_NS = "http://dlxs.org/quombat/ui"
NSMAP = {
  'fn' => XPATH_FN_NS,
  'qui' => QUI_NS,
  'glam' => "urn:umich:lib:dor:model:2026:resource:glam"
}

local_identifier = "#{options.collid}.#{options.m_id}"
dlxs_url = "https://quod.lib.umich.edu/#{options.collid[0]}/#{options.collid}/#{options.m_id}"
structmap_stylesheet = Nokogiri::XSLT(File.open("etc/dlxs2structure.xsl"))

# collect events
events = []

Cache.new(options.collid, "https://#{options.dlxs_host}/cgi/i/image") do |cache|
  entry_xml = cache.get("image-idx?cc=#{options.collid}&entryid=#{options.m_id}&view=entry&debug=xml")
  entry_doc = Nokogiri::XML(entry_xml)
  $updated_at = entry_doc.at_xpath("//TableMetadata/@update_time").value
  $updated_at = DateTime.iso8601($updated_at)
  
  # core_md
  core_md = {}
  core_md["dc.identifier"] = [local_identifier]
  entry_doc.xpath("//Record[@name='special']//Field").each do |field_el|
    abbrev = field_el['abbrev']
    next unless abbrev.start_with?("dc_")
    key = DC_MAP[abbrev]
    core_md[key] ||= []
    field_el.xpath(".//Values/Value").each do |value_el|
      core_md[key] << value_el.text
    end
  end

  # rights_statement
  rights_field_el = entry_doc.at_xpath("//Record//Field[@abbrev='dlxs_ri']") || 
                    entry_doc.at_xpath("//Record//Field[@abbrev='dc_ri']")
  rights_statement = []
  unless rights_field_el.nil?
    rights_field_el.xpath(".//Values/Value").each do |value_el|
      rights_statement << {
        "value" => value_el.inner_html,
        "$type" => "text/html"
      }
    end
  end

  # fetch the internal DLXS identifier
  istruct_isentrydiv = entry_doc.at_xpath("//BookBagForm/HiddenVars/Variable[@name='bbidno']")&.text

  # alternate_id
  alternate_id = []
  alternate_id << { type: "urn:umich:lib:dlxs:url", value: dlxs_url }
  alternate_id << { type: "urn:umich:lib:dlxs:nameresolver", value: istruct_isentrydiv.gsub(/^S-/, "IC-") } unless istruct_isentrydiv.nil?

  # build submission
  submission_path = File.join(options.output_path, DOR::calculate_uuid(local_identifier, $proposed_uuid))
  if File.exist?(submission_path)
    FileUtils.rm_rf(submission_path)
  end
  data_path = File.join(submission_path, "data")
  events_path = File.join(submission_path, "events")
  STDERR.puts ":: exporting to #{submission_path}"
  FileUtils.mkdir_p(data_path)
  FileUtils.mkdir_p(events_path)

  events = []

  File.open(File.join(submission_path, "dor-info.txt"), "w") do |f|
    f.puts "Root-Identifier: #{local_identifier}"
    f.puts "Resource-Type: #{DOR::URN("resource:glam")}"
    f.puts "Action: Commit"
    f.puts "Agent-Name: Barbara Jensen"
    f.puts "Agent-Address: mailto:bjensen@umich.edu"
    f.puts "Version-Message: Migrating #{local_identifier} from DLXS"
  end

  resource = DOR::Resource.new(local_identifier)
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

  source_metadata_sec = []
  service_metadata_sec = []

  source_md = {}
  source_md["$id"] = DOR::to_xml_id("#{local_identifier}#source")
  source_md["$node"] = local_identifier
  source_md["$function"] = [DOR::URN("function", "source")]
  entry_doc.xpath("//Record[@name='entry']//Field").each do |field_el|
    abbrev = field_el['abbrev']
    next if abbrev.start_with?("istruct_")
    next if abbrev == "dc_ri" || abbrev == "dlxs_ri"
    next if field_el['iiif-plaintext'] == "true"
    source_md[abbrev] ||= []
    field_el.xpath(".//Values/Value").each do |value_el|
      if ! value_el['link'].nil? and ! value_el['link'].include?("view=reslist")
        source_md[abbrev] << {
          "$type" => "text/html",
          "value" => %Q(<a href="#{value_el['link']}">#{value_el.text}</a>)
        }
      elsif ! value_el.elements.empty?
        source_md[abbrev] << {
          "$type" => "text/html",
          "value" => value_el.inner_html
        }
      else
        source_md[abbrev] << value_el.text
      end
    end
  end
  source_metadata_sec << source_md

  # extract m_iid metadata and filesets
  slide_urls = []
  entry_doc.xpath("//RelatedViewsMenu/Option").each do |option_el|
    value = option_el.at_xpath("Value").text
    slide_url = "image-idx?cc=#{options.collid}&entryid=#{options.m_id}&viewid=#{value}&view=entry&debug=xml"
    if istruct_isentrydiv.include?("]#{value}")
      slide_url = "image-idx?cc=#{options.collid}&entryid=#{options.m_id}&view=entry&debug=xml"
    end
    slide_urls << slide_url
  end
  if slide_urls.empty?
    slide_urls << "image-idx?cc=#{options.collid}&entryid=#{options.m_id}&view=entry&debug=xml"
  end

  # append the istruct_ <Field> into entry_doc to use in the
  # structure transform. Because not all `viewid` have 
  # istruct_ metadata.
  slide_metadata_el = entry_doc.create_element("SlideMetadata")
  entry_doc.root.add_child(slide_metadata_el)

  slide_urls.each_with_index do |slide_url, slide_index|
    slide_xml = cache.get(slide_url)
    slide_doc = Nokogiri::XML(slide_xml)

    media_info_el = slide_doc.at_xpath("//MediaInfo")
    m_id = media_info_el.at_xpath("m_id").text.downcase
    m_iid = media_info_el.at_xpath("m_iid").text.downcase
    m_fn = media_info_el.at_xpath("m_fn").text.downcase
    istruct_ms = media_info_el.at_xpath("istruct_ms").text == "P"
    slide_identifier = "#{options.collid}.#{m_id}.#{m_fn}"

    service_md = {}
    service_md["$id"] = DOR::to_xml_id("#{slide_identifier}#service")
    service_md["$node"] = slide_identifier
    service_md["$function"] = [DOR::URN("function", "service")]
    service_md["dc.identifier"] = [slide_identifier]
    slide_doc.xpath("//Record[@name='special']//Field").each do |field_el|
      abbrev = field_el['abbrev']
      next unless abbrev.start_with?("dc_")
      key = DC_MAP[abbrev]
      service_md[key] ||= []
      field_el.xpath(".//Values/Value").each do |value_el|
        service_md[key] << value_el.text
      end
    end
    service_metadata_sec << service_md

    slide_md_el = entry_doc.create_element("slide")
    slide_md_el['identifier'] = slide_identifier
    slide_md_el['m_fn'] = m_fn

    source_md = {}
    source_md["$id"] = DOR::to_xml_id("#{slide_identifier}#source")
    source_md["$node"] = slide_identifier
    source_md["$function"] = [DOR::URN("function", "source")]
    istruct_n = 0
    slide_doc.xpath("//Record[@name='entry']//Field").each do |field_el|
      abbrev = field_el['abbrev']
      next unless abbrev.start_with?("istruct_")
      source_md[abbrev] ||= []
      field_el.xpath(".//Values/Value").each do |value_el|
        if ! value_el['link'].nil? and ! value_el['link'].include?("view=reslist")
          source_md[abbrev] << {
            "$type" => "text/html",
            "value" => %Q(<a href="#{value_el['link']}">#{value_el.text}</a>)
          }
        elsif ! value_el.elements.empty?
          source_md[abbrev] << {
            "$type" => "text/html",
            "value" => value_el.inner_html
          }
        else
          source_md[abbrev] << value_el.text
        end
        slide_md_el << field_el.dup
        istruct_n += 1
      end
    end
    source_metadata_sec << source_md unless istruct_n == 0
    slide_metadata_el << slide_md_el unless istruct_n == 0

    # there is no asset attached to this slide
    unless istruct_ms
      next
    end

    # download file and configure fileset resource
    pending_id = "info:pending/#{options.collid}/#{m_fn}"

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
          "dc.identifier" => [ "#{options.collid}/#{m_fn}" ],
          "dc.title" => [ m_fn ]
        }),
        updated_at: $updated_at
      )
    )
    
    image_id = "api/image/#{options.collid}:#{m_id}:#{m_iid}"
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

    event = DOR::Event.new(
      event_type: "mee",
      date_time: $updated_at,
      outcome: "success",
      detail: "Extracted technical metadata for #{asset_file.content_path} using jhove",
      objects: [ 
        DOR::Agent.new(identifier: asset_file.id, role: "src"),
        DOR::Agent.new(identifier: asset_md_file.id, role: "out")
      ],
      agents: [ DOR::Agent.new(identifier: "https://jhove.openpreservation.org/", role: "exe") ]
    )

    if slide_doc.xpath("//Field[@iiif-plaintext='true']").any?

      plaintext_text = []
      tmp = {}
      plaintext_el = slide_doc.at_xpath("//Field[@iiif-plaintext='true']")
      plaintext_mime_type = "text/plain"
      plaintext_el.xpath("Values/Value").each do |value_el|
        tmp_key = value_el['abbrev'] || plaintext_el['abbrev']
        tmp[tmp_key] ||= []
        if value_el.elements.empty?
          tmp[tmp_key] << value_el.text
          plaintext_text << value_el.text
        else
          tmp[tmp_key] << value_el.inner_html
          plaintext_text << value_el.inner_html
          plaintext_mime_type = "text/html"
        end
      end

      # this is dumb, sorry
      if options.collid == 'tinder'
        plaintext_text = tmp["fulltext#{slide_index + 1}"] || []
      end

      plaintext_text = plaintext_text.join("\n")
      unless plaintext_text.empty?

        plaintext_asset = {
          basename: m_fn,
          content: plaintext_text,
          producer: 'zooniverse'
        }

        plaintext_path = DLXS::Utils::generate_plaintext(fileset_resource.resource_path, plaintext_asset)
        fileset_resource.add_file(
          plaintext_file = DOR::ResourceFile.new(
            id: File.join(fileset_resource.id, plaintext_path),
            parent: fileset_resource.id,
            content_path: File.basename(plaintext_path),
            mime_type: plaintext_mime_type,
            interaction_model: DOR::URN("file", plaintext_mime_type == "text/html" ? "html" : "plaintext"),
            updated_at: $updated_at,
            filename: File.basename(plaintext_path),
            function: [DOR::URN("function", "service"), DOR::URN("function", "source")]
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

        event = DOR::Event.new(
          event_type: "mee",
          date_time: $updated_at,
          outcome: "success",
          detail: "Extracted technical metadata for #{plaintext_file.content_path} using jhove",
          objects: [ 
            DOR::Agent.new(identifier: plaintext_file.id, role: "src"),
            DOR::Agent.new(identifier: plaintext_md_file.id, role: "out")
          ],
          agents: [ DOR::Agent.new(identifier: "https://jhove.openpreservation.org/", role: "exe") ]
        )
      end

    end

    event = DOR::Event.new(
      event_type: "ing",
      date_time: $updated_at,
      outcome: "success",
      detail: "Submitted #{pending_id} for packaging",
      objects: [ 
        DOR::Agent.new(identifier: pending_id, role: "src"),
      ],
      agents: [ DOR::Agent.new(identifier: "mailto:rjmcinty@umich.edu", role: "imp") ]
    )

  end

  resource.add_file(
    DOR::ResourceFile.new(
      id: File.join(resource.id, "#{local_identifier}~md.service.json"),
      parent: resource.id,
      content_path: "#{local_identifier}~md.service.json",
      mime_type: "application/json",
      interaction_model: DOR::URN("metadata"),
      function: [DOR::URN("function", "service")],
      updated_at: $updated_at,
      content: JSON.pretty_generate(service_metadata_sec)
    )
  )

  resource.add_file(
    DOR::ResourceFile.new(
      id: File.join(resource.id, "#{local_identifier}~md.source.json"),
      parent: resource.id,
      content_path: "#{local_identifier}~md.source.json",
      mime_type: "application/json",
      interaction_model: DOR::URN("metadata"),
      function: [DOR::URN("function", "source")],
      updated_at: $updated_at,
      content: JSON.pretty_generate(source_metadata_sec)
    )
  )

  # structure
  structmap = structmap_stylesheet.transform(
    entry_doc,
    Nokogiri::XSLT.quote_params({ "local_identifier" => local_identifier })
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

  # rights statement
  unless rights_statement.nil? or rights_statement.empty?
    rights_md = {}
    rights_md["dc.rights"] = rights_statement
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

  event = DOR::Event.new(
    event_type: "ing",
    date_time: $updated_at,
    outcome: "success",
    detail: "Submitted #{resource.id} for ingestion",
    objects: [ 
      DOR::Agent.new(identifier: resource.id, role: "src"),
    ],
    agents: [ DOR::Agent.new(identifier: "mailto:rjmcinty@umich.edu", role: "imp") ]
  )

  DOR::Headers.update_resource_headers(resource.resource_path)

  # events
  DOR::Event.save!(events_path)
end

puts "-30-"
