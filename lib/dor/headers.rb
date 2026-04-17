require 'digest'
require 'uuidtools'

module DOR::Headers
  module_function

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

  def update_header(header_file)
    header_data = JSON.parse(File.read(header_file))
    content_path = header_data["contentPath"]
    resource_file = File.join(File.dirname(File.dirname(header_file)), content_path)
    # STDERR.puts "---- #{content_path} -> #{resource_file}"
    header_data["digests"] = ["urn:sha-512:#{calculate_sha512(resource_file)}"]
    header_data["contentSize"] = File.size(resource_file)
    return header_data
  end

  def update_resource_headers(resource_path)
    remove_path = File.dirname(resource_path) + "/"
    package_resources = Dir.glob(File.join(resource_path, "**", "core.dor.json")).select { |f| File.file?(f) }
    package_resources.each do |core_path|
      STDERR.puts "### #{core_path}"
      resource_path = File.dirname(core_path)
      resource_id = resource_path.sub(remove_path, "")
      header_files = Dir.glob(File.join(resource_path, ".dor", "*")).select { |f| File.file?(f) }
      header_files.each do |header_file|
        ## STDERR.puts header_file
        header_data = update_header(header_file)
        File.open(header_file, "w") do |f|
          f.puts(JSON.pretty_generate(header_data))
        end
      end
    end
  end  

end