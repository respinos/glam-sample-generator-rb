require_relative '../xml'
require_relative '../../dor'
require_relative '../../dor/headers'

require 'json'
require 'cgi'

module DLXS

  class CGI

    class Context
      attr_accessor :collid, :partner, :idno, :cache, :submission

      def initialize(collid:, partner:, idno:, cache:, submission:)
        @collid = collid
        @partner = partner
        @idno = idno
        @cache = cache
        @submission = submission
      end
    end

    class Text < CGI
      attr_accessor :collid, :partner, :idno, :cache, :updated_at

      def initialize(context:)
        @context = context
        @collid = context.collid
        @partner = context.partner
        @idno = context.idno
        @cache = context.cache
        @local_identifier = context.submission.id
      end

      def export_submission
        fetch_toc
        extract_core_metadata
        generate_resource
        DOR::Headers.update_resource_headers(@resource.resource_path)
        DOR::Event.save!(submission: @context.submission)
      end
    
      def fetch_toc
        toc_xml = @cache.get("text-idx?cc=#{@collid}&idno=#{@idno}&view=toc&debug=qui").to_s
        @toc_doc = Nokogiri::XML(toc_xml)  { |config| config.default_xml.noblanks }
        updated_at = @toc_doc.at_xpath("//qui:metadata/@modified").value
        @updated_at = DateTime.iso8601(updated_at)
      end

      def generate_source_text
        text_xml = @cache.get("text-idx?cc=#{@collid}&idno=#{@idno}&debug=xml&view=text&_=xyzzy&rgn=main&rewrap=no").to_s
        text_doc = Nokogiri::XML(text_xml)  { |config| config.default_xml.noblanks }

        tei_stylesheet = Nokogiri::XSLT(File.open("etc/tei3to5.xsl"))
        @teip5_doc = tei_stylesheet.transform(text_doc, Nokogiri::XSLT.quote_params({ "idno" => @idno, "encodingtype" => @encodingtype }))

        tei_filename = "#{@idno}~md.tei.xml"
        @resource.add_file(
          DOR::ResourceFile.new(
            id: File.join(@resource.id, tei_filename),
            parent: @resource.id,
            content_path: tei_filename,
            mime_type: "application/xml",
            interaction_model: DOR::URN("file", "tei"),
            function: DOR::URN("function", "source"),
            updated_at: @updated_at,
            content: @teip5_doc.to_xml
          )
        )        
      end

      def extract_core_metadata
        @core_md = {}
        @core_md["dc.identifier"] = [@idno]
        @toc_doc.xpath('//qui:metadata/qui:field').each do |field_el|
          key = "dc.#{field_el['key']}"
          @core_md[key] = []
          field_el.xpath('.//qui:value').each do |value_el|
            if key == 'dc.useguidelines'
              p_els = value_el.xpath(".//xhtml:p")
              @core_md[key] << p_els.first.inner_text
              link_el = value_el.at_xpath(".//xhtml:a")
              unless link_el.nil?
                @core_md[key] << { type: "uri", value: link_el['href'] }
              end
            else
              @core_md[key] << value_el.text
            end
          end
        end
        @bookmarkable_url = @core_md.delete('dc.bookmark')&.first
        @rights_statement = @core_md.delete("dc.useguidelines")
        @core_md.delete("dc.citation")

        @encodingtype = @toc_doc.xpath("//qui:metadata[@slot='root']/@encoding-type").text

        @metadata_sec = []
        @metadata_sec << {
          "$id": DOR::to_xml_id("#{@idno}#source"),
          "$node": @idno,
          "$function": [DOR::URN("function", "service")],
        }
        @metadata_sec[0].merge!(@core_md)
      end

      def generate_resource
        @resource = DOR::Resource.new(@local_identifier)
        @resource.setup!(@context.submission.data_path)
        @resource.add_file(
          DOR::ResourceFile.new(
            id: @resource.id,
            parent: nil,
            content_path: "core.dor.json",
            mime_type: "application/json",
            interaction_model: DOR::URN("resource:glam"),
            alternate_id: extract_alternate_identifiers,
            partner_id: "info:partner/#{@partner}",
            content: JSON.pretty_generate(@core_md),
            updated_at: @updated_at
          )
        )
        
        generate_rights_metadata

        generate_source_text

        generate_structure_metadata

        if has_images?
          generate_filesets
        end

        DOR::Event.new(
          event_type: "ing",
          date_time: @updated_at,
          outcome: "success",
          detail: "Submitted #{@resource.id} for ingestion",
          objects: [ 
            DOR::Agent.new(identifier: @resource.id, role: "src"),
          ],
          agents: [ DOR::Agent.new(identifier: "mailto:sooty@umich.edu", role: "imp") ]
        )

      end

      def extract_alternate_identifiers
        alternate_id = []
        dlxs_url = "https://quod.lib.umich.edu/#{@collid[0]}/#{@collid}/#{@idno}"
        if ! @bookmarkable_url.nil? and @bookmarkable_url != dlxs_url
          alternate_id << { type: "urn:umich:lib:dlxs:url", value: dlxs_url }
          alternate_id << { type: "urn:umich:lib:dlxs:nameresolver", value: @bookmarkable_url }
        else
          alternate_id << { type: "urn:umich:lib:dlxs:url", value: dlxs_url }
        end
        alternate_id
      end

      def has_images?
        @toc_doc.xpath("//qui:block[@slot='contents']//qui:link[contains(@href, 'pageviewer-idx')]").any?
      end

      def generate_rights_metadata
        unless @rights_statement.nil? or @rights_statement.empty?
          rights_md = {}
          rights_md["dc.rights"] = @rights_statement
          @resource.add_file(
            DOR::ResourceFile.new(
              id: File.join(@resource.id, "rights.dor.json"),
              parent: @resource.id,
              content_path: "rights.dor.json",
              mime_type: "application/json",
              interaction_model: DOR::URN("rights"),
              updated_at: @updated_at,
              content: JSON.pretty_generate(rights_md)
            )
          )
        end
      end

      def generate_structure_metadata
        structmap_stylesheet = Nokogiri::XSLT(File.read("etc/tei2structure.xsl"))
        structmap_doc = structmap_stylesheet.transform(@teip5_doc,
            Nokogiri::XSLT.quote_params({ "idno" => @idno, "encodingtype" => @encodingtype })
        )
        @resource.add_file(
          DOR::ResourceFile.new(
            id: File.join(@resource.id, "structure.dor.xml"),
            parent: @resource.id,
            content_path: "structure.dor.xml",
            mime_type: "application/xml",
            interaction_model: DOR::URN("structure"),
            updated_at: @updated_at,
            content: structmap_doc.to_xml
          )
        )
      end
    end      

    def generate_filesets
      pageviewer_link = @toc_doc.xpath("//qui:block[@slot='contents']//qui:link[contains(@href, 'pageviewer-idx')]").first
      pageviewer_href = ::CGI.unescape(pageviewer_link['href'].split('/cgi/t/text/').last)
      pageviewer_xml = cache.get(pageviewer_href).to_s
      pageviewer_doc = Nokogiri::XML(pageviewer_xml)  { |config| config.default_xml.noblanks }
      pageviewer_doc.xpath('//qui:viewer/fn:map//fn:array[@key="sequences"]/fn:map/fn:array[@key="canvases"]/fn:map', **NSMAP).each do |canvas_el|
        image_id = canvas_el.xpath('.//fn:array[@key="images"]/fn:map/fn:map[@key="resource"]/fn:map[@key="service"]/fn:string[@key="@id"]', **NSMAP).text
        pagetext_href = canvas_el.xpath('.//fn:map[@key="seeAlso"]/fn:string[@key="@id"]', **NSMAP).text
        pagetext_href = pagetext_href.split('/cgi/t/text/').last unless pagetext_href.empty?

        Fileset.new(
          resource: @resource,
          context: @context,
          image_id: image_id,
          pagetext_href: pagetext_href,
          updated_at: @updated_at,
        ).generate_fileset
      end
    end

    class Fileset
      attr_accessor :resource, :context, :image_id, :pagetext_href, :updated_at
      def initialize(resource:, context:, updated_at:, image_id:, pagetext_href:)
        @resource = resource
        @context = context
        @idno = @context.idno
        @image_id = image_id
        @pagetext_href = pagetext_href
        @updated_at = updated_at
        @cache = @context.cache
      end

      def generate_fileset
        @m_fn = m_fn = @image_id.split(":").last
        pending_id = "info:pending/#{@idno}/#{m_fn}"

        @fileset_resource = DOR::Resource.new("#{@resource.id}/#{m_fn}")
        @fileset_resource.setup!(@context.submission.data_path)

        @fileset_resource.add_file(
          DOR::ResourceFile.new(
            id: @fileset_resource.id,
            parent: @resource.id,
            content_path: "core.dor.json",
            mime_type: "application/json",
            interaction_model: DOR::URN("resource:fileset"),
            alternate_id: [
              { type: DOR::URN("packaging", "fileset"), value: pending_id },
            ],
            partner_id: "info:partner/#{@context.partner}",
            content: JSON.pretty_generate({
              "dc.identifier" => [ "#{@idno}/#{m_fn}" ],
              "dc.title" => [ m_fn ]
            }),
            updated_at: @updated_at
          )
        )

        generate_image_file
        generate_text_file

        DOR::Event.new(
          event_type: "ing",
          date_time: @updated_at,
          outcome: "success",
          detail: "Submitted #{pending_id} for packaging",
          objects: [ 
            DOR::Agent.new(identifier: pending_id, role: "src"),
          ],
          agents: [ DOR::Agent.new(identifier: "mailto:sooty@umich.edu", role: "imp") ]
        )        

      end

      def generate_image_file
        image_data = @cache.get("#{@image_id}/full/250,/0/native.tif")
        asset_path = "#{@m_fn}.tif"
        @fileset_resource.add_file(
          asset_file = DOR::ResourceFile.new(
            id: File.join(@resource.id, @m_fn),
            parent: @resource.id,
            content_path: "#{@m_fn}.tif",
            mime_type: "image/tiff",
            interaction_model: DOR::URN("file:image"),
            content: image_data,
            updated_at: @updated_at
          )
        )

        asset_md_path = DLXS::Utils::generate_techmd(@fileset_resource.resource_path, asset_path)
        @fileset_resource.add_file(
          asset_md_file = DOR::ResourceFile.new(
            id: File.join(@fileset_resource.id, asset_md_path),
            parent: @fileset_resource.id,
            content_path: File.basename(asset_md_path),
            mime_type: "application/xml",
            interaction_model: DOR::URN("metadata", "mix"),
            updated_at: @updated_at,
            filename: File.basename(asset_md_path),
            function: [DOR::URN("function", "technical")]
          )
        )

        event = DOR::Event.new(
          event_type: "mee",
          date_time: @updated_at,
          outcome: "success",
          detail: "Extracted technical metadata for #{asset_file.content_path} using jhove",
          objects: [ 
            DOR::Agent.new(identifier: asset_file.id, role: "src"),
            DOR::Agent.new(identifier: asset_md_file.id, role: "out")
          ],
          agents: [ DOR::Agent.new(identifier: "https://jhove.openpreservation.org/", role: "exe") ]
        )
      end

      def generate_text_file
        if @pagetext_href.nil? || @pagetext_href.empty?
          return
        end
        pagetext_xml = @cache.get(@pagetext_href + ";debug=qui")
        pagetext_doc = Nokogiri::XML(pagetext_xml)  { |config| config.default_xml.noblanks }
        content = pagetext_doc.xpath('//tei:ResultFragment/tei:P', **NSMAP).map(&:inner_text).join("\n\n").strip

        unless content.empty?
          plaintext_asset = {
            basename: @m_fn,
            content: content,
            producer: 'primeocr'
          }

          plaintext_path = DLXS::Utils::generate_plaintext(@fileset_resource.resource_path, plaintext_asset)

          @fileset_resource.add_file(
            plaintext_file = DOR::ResourceFile.new(
              id: File.join(@fileset_resource.id, plaintext_path),
              parent: @fileset_resource.id,
              content_path: File.basename(plaintext_path),
              mime_type: "text/plain",
              interaction_model: DOR::URN("file", "text"),
              updated_at: @updated_at,
              filename: File.basename(plaintext_path),
              function: [DOR::URN("function", "derived")]
            )
          )

          plaintext_md_path = DLXS::Utils::generate_techmd(@fileset_resource.resource_path, plaintext_path)

          @fileset_resource.add_file(
            plaintext_md_file = DOR::ResourceFile.new(
              id: File.join(@fileset_resource.id, plaintext_md_path),
              parent: @fileset_resource.id,
              content_path: File.basename(plaintext_md_path),
              mime_type: "application/xml",
              interaction_model: DOR::URN("metadata", "textmd"),
              updated_at: @updated_at,
              filename: File.basename(plaintext_md_path),
              function: [DOR::URN("function", "technical")]
            )
          )

          DOR::Event.new(
            # id: DOR::calculate_uuid("#{asset[:basename]}.plaintext.mee", $default_uuid),
            event_type: "mee",
            date_time: @updated_at,
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

    end

  end
end