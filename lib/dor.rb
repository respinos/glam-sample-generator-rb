require 'uuidtools'
require 'securerandom'
require 'builder'

require 'zlib'

module DOR
  module_function

  $default_uuid = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, "fixtures")
  $fileset_uuid = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, "fileset")
  $submission_uuid = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, "submission")
  $proposed_uuid = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, "proposed")

  PREMIS_MAP = {
    "mee" => "metadata extraction",
    "src" => "source",
    "out" => "outcome",
    "exe" => "executing program",
    "ing" => "ingestation",
    "imp" => "implementer",
  }


  def URN(*leaf)
    "urn:umich:lib:dor:model:2026:#{leaf.join(':')}"
  end

  def calculate_uuid(resource_path, namespace)
    UUIDTools::UUID.sha1_create(namespace, resource_path).to_s
  end

  def to_xml_id(str)
      "_#{Zlib.crc32(str).to_s(16)}"
  end

  def generate_past_uuid7(time, seed: 2026)
    # Create a seeded pseudo-random number generator
    STDERR.puts "::: ::: #{time} <- #{seed}"
    prng = Random.new(seed)

    # 1. Timestamp (48 bits / 12 hex chars)
    if time.is_a?(String)
    elsif time.is_a?(DateTime)
      time = time.to_time
    end
    ms = (time.to_f * 1000).to_i
    hex_ms = ms.to_s(16).rjust(12, '0')

    # 2. Generate 10 random bytes and convert to hex
    # unpack1('H*') returns a single hex string from the byte array
    rand_hex = prng.bytes(10).unpack1('H*')

    # 3. Construct the UUID components
    part1 = hex_ms[0..7]
    part2 = hex_ms[8..11]
    
    # Version 7 + next 3 hex chars from our random pool
    part3 = "7#{rand_hex[0..2]}"
    
    # Variant 2 (8, 9, a, or b) + next 3 hex chars
    # We'll stick to '8' for total predictability in tests
    part4 = "8#{rand_hex[3..5]}"
    
    # The remaining 12 hex chars
    part5 = rand_hex[6..17]

  "#{part1}-#{part2}-#{part3}-#{part4}-#{part5}"
  end

  class Submission
    attr_accessor :id, :data_path, :events_path
    def initialize(output_path:)
      @output_path = output_path
    end

    def setup!(local_identifier:)
      @id = DOR::calculate_uuid(local_identifier, $submission_uuid)
      @submission_path = File.join(@output_path, @id)
      if File.exist?(@submission_path)
        FileUtils.rm_rf(@submission_path)
      end

      @data_path = File.join(@submission_path, "data")
      @events_path = File.join(@submission_path, "events")
      FileUtils.mkdir_p(@data_path)
      FileUtils.mkdir_p(@events_path)
    end

    def open(filename, &block)
      STDERR.puts "#{@submission_path} :: #{filename}"
      File.open(File.join(@submission_path, filename), "w", &block)
    end
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
        unless resource_file.partner_id.nil?
          datum[:partnerId] = resource_file.partner_id
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

    attr_accessor :id, :parent, :content_path, :mime_type, :interaction_model, :alternate_id, :content, :updated_at, :partner_id, :filename, :function

    def initialize(id:, parent:, content_path:, mime_type:, interaction_model:, alternate_id: [], content: nil, updated_at:, partner_id: nil, filename: nil, function: nil)
      @id = id
      @parent = parent
      @content_path = content_path
      @mime_type = mime_type
      @interaction_model = interaction_model
      @alternate_id = alternate_id
      @content = content
      @filename = filename
      @updated_at = updated_at
      @partner_id = partner_id
      @function = function
    end
  end

  class Agent
    attr_accessor :identifier, :role
    def initialize(identifier:, role:)
      @identifier = identifier
      @role = role
    end
  end

  class Event
    @@seed = 2026
    @@events = []

    attr_accessor :id, :date_time, :event_type, :outcome, :detail, :objects, :agents

    def self.save!(submission:)
      events_path = submission.events_path
      @@events.each do |event|
        event_filename = File.join(events_path, "#{event.id}.premis.xml")
        event.save!(event_filename)
      end
    end

    def initialize(date_time:, event_type:, outcome:, detail:, objects: [], agents: [])
      @@seed += 1
      @id = DOR::generate_past_uuid7(date_time, seed: @@seed)
      @date_time = date_time
      @event_type = event_type
      @detail = detail
      @outcome = outcome
      @objects = objects
      @agents = agents
      @@events << self
      STDERR.puts "-- #{@@events.size}"
    end

    def save!(event_filename)
      builder = Builder::XmlMarkup.new(:indent => 2)
      builder.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
      xml = builder.premis :event, "xmlns:premis" => "http://www.loc.gov/premis/v3" do |x|
        x.premis :eventIdentifier do |x|
          x.premis :eventIdentifierType, "UUID"
          x.premis :eventIdentifierValue, self.id
        end
        x.premis :eventType,
          DOR::PREMIS_MAP[self.event_type],
          authority: "premis_event_type", 
          authorityURI: "http://id.loc.gov/vocabulary/premis/eventType", 
          valueURI: "http://id.loc.gov/vocabulary/premis/eventType/#{self.event_type}"
        x.premis :eventDateTime, self.date_time.to_datetime.to_s
        x.premis :eventDetailInformation do
          x.premis :eventDetail, self.detail
        end
        x.premis :eventOutcomeInformation do
          x.premis :eventOutcome, self.outcome
        end
        self.agents.each do |agent|
          x.premis :linkingAgentIdentifier do |x|
            x.premis :linkingAgentIdentifierType, "local"
            x.premis :linkingAgentIdentifierValue, agent.identifier
            x.premis :linkingAgentRole, DOR::PREMIS_MAP[agent.role]
          end
        end
        self.objects.each do |object|
          x.premis :linkingObjectIdentifier do |x|
            x.premis :linkingObjectIdentifierType, "local"
            x.premis :linkingObjectIdentifierValue, object.identifier
            x.premis :linkingObjectRole, DOR::PREMIS_MAP[object.role]
          end
        end
      end
      File.open(event_filename, "w") do |f|
        f.puts(xml)
      end      
    end
  end

end