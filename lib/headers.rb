require 'digest'
require 'uuidtools'

$default_uuid = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, "fixtures")
$fileset_uuid = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, "fileset")

module Headers

  module_function

  def DOR(leaf)
    "urn:umich:lib:dor:model:2026:#{leaf}"
  end

  def calculate_uuid(resource_path, namespace)
    UUIDTools::UUID.sha1_create(namespace, resource_path).to_s
  end

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


  def guess_file_info(file_path)
    info = {}

    case File.basename(file_path)
    when "core.dor.json"
      parts = File.dirname(file_path).split(File::SEPARATOR)
      info["interactionModel"] = parts.length == 1 ? DOR("resource:glam") : DOR("resource:fileset")
      info["mimeType"] = "application/json"
      STDERR.puts parts
    when "structure.dor.xml"
      info["interactionModel"] = DOR("structure")
      info["mimeType"] = "application/xml"
    when "rights.dor.json"
      info["interactionModel"] = DOR("rights")
      info["mimeType"] = "application/json"
    else
    end
    return info unless info.empty?

    case File.extname(file_path).downcase
    when ".json"
      info["interactionModel"] = DOR("file:metadata")
      info["mimeType"] = "application/json"
    when ".tif", ".tiff"
      info["interactionModel"] = DOR("file:data")
      info["mimeType"] = "image/tiff"
      info["filename"] = File.basename(file_path)
    when ".txt"
      info["interactionModel"] = DOR("file:data")
      info["mimeType"] = "text/plain"
      info["filename"] = File.basename(file_path)
    when ".xml"
      info["interactionModel"] = DOR("file:data")
      info["mimeType"] = "application/xml"
      info["filename"] = File.basename(file_path)
    else
      raise "Unknown file type for #{file_path}"
    end
    info
  end

  def generate_header(resource_id, resource_file)
      id = if File.basename(resource_file) == "core.dor.json"
        File.join("info:root", resource_id)
      else
        File.join("info:root", resource_id, File.basename(resource_file))
      end
      info = if File.basename(resource_file) == "core.dor.json"
        parts = File.dirname(id).split(File::SEPARATOR)
        {
          "interactionModel" => parts.length == 1 ? DOR("resource:glam") : DOR("resource:fileset"),
          "mimeType" => "application/json"  
        }
      else
        guess_file_info(id)
      end
      header_file = File.join(File.dirname(resource_file), ".dor", File.basename(resource_file) + ".json")
      header_data = {}
      header_data["id"] = id
      header_data["parent"] = File.dirname(id)
      header_data["systemIdentifier"] = if File.basename(resource_file) == "core.dor.json" and header_data["parent"] > 'info:root'
        calculate_uuid(File.dirname(resource_file), $fileset_uuid)
      else
        calculate_uuid(File.basename(resource_file), $default_uuid)
      end
      header_data["interactionModel"] = info["interactionModel"]
      header_data["contentSize"] = File.size(resource_file)
      unless info["mimeType"].nil?
        header_data["mimeType"] = info["mimeType"]
      end
      unless info["filename"].nil?
        header_data["filename"] = info["filename"]
      end
      header_data["digests"] = ["urn:sha-512:#{calculate_sha512(resource_file)}"]
      header_data["updatedAt"] = File.mtime(resource_file).utc.iso8601
      header_data["updatedBy"] = "dlxsadm"
      header_data["deleted"] = false
      header_data["visibility"] = "visible"
      header_data["contentPath"] =  File.basename(resource_file)
      header_data["headersVersion"] = "1.0"
      return header_file, header_data
  end

  def process_path(resource_path)
    remove_path = File.dirname(resource_path) + "/"
    package_resources = Dir.glob(File.join(resource_path, "**", "core.dor.json")).select { |f| File.file?(f) }
    package_resources.each do |core_path|
      resource_path = File.dirname(core_path)
      resource_id = resource_path.sub(remove_path, "")
      resource_files = Dir.glob(File.join(resource_path, "*")).select { |f| File.file?(f) }
      resource_files.each do |resource_file|
        header_file, header_data = generate_header(resource_id, resource_file)
        File.open(header_file, "w") do |f|
          f.write(JSON.pretty_generate(header_data))
        end
      end
    end
  end
end