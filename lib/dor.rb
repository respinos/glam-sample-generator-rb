require 'uuidtools'

module DOR
  module_function

  $default_uuid = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, "fixtures")
  $fileset_uuid = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, "fileset")
  $submission_uuid = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, "submission")


  def URN(*leaf)
    "urn:umich:lib:dor:model:2026:#{leaf.join(':')}"
  end

  def calculate_uuid(resource_path, namespace)
    UUIDTools::UUID.sha1_create(namespace, resource_path).to_s
  end

  class Resource
    attr_accessor :id, :resource_path, :header_path, :interaction_model, :mime_type, :digests, :content_size

    def initialize(id)
      @id = id
    end

    def setup!(output_path)
      @resource_path = File.join(output_path, @id)
      if File.exist?(@resource_path)
        FileUtils.rm_rf(@resource_path)
      end
      @header_path = File.join(@resource_path, ".dor")
      FileUtils.mkdir_p(@header_path)
    end

    def add_file(resource_file)
      unless resource_file.content.nil?
        File.open(File.join(@resource_path, resource_file.content_path), "w") do |f|
          f.puts(resource_file.content)
        end
      end
      File.open(File.join(@header_path, "#{resource_file.content_path}.json"), "w") do |f|
        datum = {}
        datum[:id] = "info:root/#{resource_file.id}"
        datum[:parent] = resource_file.parent.nil? ? "info:root" : File.join("info:root", resource_file.parent.to_s)
        datum[:systemIdentifier] = DOR::calculate_uuid(datum[:id], $default_uuid) if $include_system_identifiers
        unless resource_file.stakeholder_id.nil?
          datum[:stakeholderId] = resource_file.stakeholder_id
        end
        unless resource_file.alternate_id.empty?
          datum[:alternateId] = resource_file.alternate_id
        end
        datum[:interactionModel] = resource_file.interaction_model
        unless resource_file.function.nil?
          datum[:function] = resource_file.function
        end
        datum[:contentSize] = 0
        datum[:mimeType] = resource_file.mime_type
        unless resource_file.filename.nil?
          datum[:filename] = resource_file.filename
        end
        datum[:digests] = []
        if $include_updated_by
          datum[:updatedAt] = resource_file.updated_at
          datum[:updatedBy] = "dlxsadm@dlxs.umich.edu"
        else
          datum[:updated] = resource_file.updated_at
        end
        datum[:deleted] = false
        datum[:visibility] = "visible"
        datum[:contentPath] = resource_file.content_path
        datum[:headersVersion] = "1.0"
        f.puts(JSON.pretty_generate(datum))
      end
    end
  end

  class ResourceFile

    attr_accessor :id, :parent, :content_path, :mime_type, :interaction_model, :alternate_id, :content, :updated_at, :stakeholder_id, :filename, :function

    def initialize(id:, parent:, content_path:, mime_type:, interaction_model:, alternate_id: [], content: nil, updated_at:, stakeholder_id: nil, filename: nil, function: nil)
      @id = id
      @parent = parent
      @content_path = content_path
      @mime_type = mime_type
      @interaction_model = interaction_model
      @alternate_id = alternate_id
      @content = content
      @filename = filename
      @updated_at = updated_at
      @stakeholder_id = stakeholder_id
      @function = function
    end
  end

end