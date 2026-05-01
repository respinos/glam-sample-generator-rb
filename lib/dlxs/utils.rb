require 'open3'
require 'debug'
require 'tty-command'
require 'nokogiri'
require 'pp'

module DLXS
  module Utils
    module_function

    def safe_filename(filename)
      filename.gsub(/[^0-9A-Za-z.\-]+/, '_')
    end

    def generate_asset(resource_path, asset)
      cmd = TTY::Command.new(printer: :null)      
      jp2_path = File.join("/quod/asset", asset[:filename])
      actual_jp2_path = File.join(
        "/quod/asset",
        File.dirname(asset[:filename]),
        File.readlink(jp2_path)
      )
      tif_filename = asset[:basename].downcase + ".tif"
      out, status = cmd.run(
        "kdu_expand",
        "-i", actual_jp2_path,
        "-o", "/tmp/#{tif_filename}",
        "-reduce", asset[:levels].to_s
      )
      out, status = cmd.run(
        "convert",
        "/tmp/#{tif_filename}",
        File.join(resource_path, tif_filename)
      )
      tif_filename
    end

    def generate_obj(resource_path, asset)
      cmd = TTY::Command.new(printer: :null)
      original_path = File.join("/quod/obj", asset[:filename])
      obj_filename = asset[:basename].downcase + "." + asset[:ext]
      if asset[:mimetype] == "image/jp2"
        out, status = cmd.run(
          "kdu_expand",
          "-i", original_path,
          "-o", "/tmp/#{obj_filename}.tif",
          "-reduce", asset[:levels].to_s
        )
        out, status = cmd.run(
          "kdu_compress",
          "-i", "/tmp/#{obj_filename}.tif",
          "-o", File.join(resource_path, obj_filename)
        )
      else
        h = asset[:height] / (2 ** asset[:levels])
        out, status = cmd.run(
          "convert",
          original_path,
          "-geometry", "x#{h}",
          "/tmp/#{obj_filename}",
        )
        out, status = cmd.run(
          "convert",
          "/tmp/#{obj_filename}",
          File.join(resource_path, obj_filename)
        )
      end
      
      obj_filename
    end    

    def generate_plaintext(resource_path, asset)
      txt_filename = "#{asset[:basename]}.#{asset[:producer]}.txt"
      File.open(File.join(resource_path, txt_filename), "w") do |f|
        f.puts(asset[:content])
      end
      txt_filename
    end

    def generate_techmd(resource_path, asset_path)
      cmd = TTY::Command.new(printer: :null)
      asset_filename = File.join(resource_path, asset_path)
      md_filename = File.basename(asset_filename) + \
      if asset_filename.end_with?(".tif")
        then "~md.mix.xml"
      elsif asset_filename.end_with?(".jp2")
        then "~md.mix.xml"
        elsif asset_filename.end_with?(".txt") then "~md.textmd.xml"
        elsif asset_filename.end_with?(".html") then "~md.textmd.xml"
        else "~md.unknown.xml"
        end

      is_jhove_installed = cmd.run!("bash -c 'command -v exiftool'").success?
      unless is_jhove_installed
        if asset_filename.end_with?(".tif")
          return generate_techmd_image(resource_path, asset_path, asset_filename, md_filename)
        elsif asset_filename.end_with?(".txt")
          return generate_techmd_text(resource_path, asset_path, asset_filename, md_filename)
        elsif asset_filename.end_with?(".html")
          return generate_techmd_text(resource_path, asset_path, asset_filename, md_filename)
        else
          raise "Jhove is not installed and the file type is not supported for techMD generation without Jhove."
        end
      end
      
      argv = [ "jhove",
        "-c", "etc/jhove.conf",
        "-h", "xml" ]
      if asset_filename.end_with?(".txt")
        argv << "-m" << "UTF8-hul"
      elsif asset_filename.end_with?(".tif")
        argv << "-m" << "TIFF-hul"
      elsif asset_filename.end_with?(".jp2")
        argv << "-m" << "JPEG2000-hul"
      else
        argv << "-m" << "TIFF-hul"
      end
      argv << asset_filename
      out, status = cmd.run(*argv)
      doc = Nokogiri::XML(out.to_s) { |config| config.default_xml.noblanks }
      jhove_el = if asset_filename.end_with?(".tif") or asset_filename.end_with?(".jp2")
      then
        doc.at_xpath('//mix:mix', 'mix' => 'http://www.loc.gov/mix/v20')
      elsif asset_filename.end_with?(".txt")
        doc.at_xpath('//textmd:textMD', 'textmd' => 'info:lc/xmlns/textMD-v3')
      else
        doc.root
      end
      if jhove_el.nil?
        STDERR.puts out.to_s
        exit
      end
      File.open(File.join(resource_path, md_filename), "w") do |f|
        f.write(jhove_el.to_xml(indent: 2, encoding: 'UTF-8'))
      end
      md_filename
    end

    def generate_techmd_image(resource_path, asset_path, asset_filename, md_filename)
      # Initialize Exiftool and fetch metadata
      # file[:pathandfilename] assumes 'file' is a Hash

      require 'exifr/tiff'

      metadata = EXIFR::TIFF.new(asset_filename)
      
      # Determine Resolution Unit
      unit = case metadata.resolution_unit
            when 2 then 'in.'
            when 3 then 'cm'
            else 'no absolute unit'
            end

      # Determine Byte Order
      byte_order = 'little endian'

      # Initialize Builder
      xml = Builder::XmlMarkup.new(indent: 2)

      xml.mix :mix, "xmlns:mix" => "http://www.loc.gov/mix/v20" do
        xml.mix :BasicDigitalObjectInformation do
          xml.mix :FormatDesignation do
            xml.mix :formatName, "image/tiff"
          end
          
          xml.mix :ObjectIdentifier do
            xml.mix :objectIdentiferType, "EXIFR (Ruby)"
            xml.mix :objectIdentifierValue, "#{File.basename(asset_filename)}"
          end
          
          xml.mix :byteOrder, byte_order
          
          xml.mix :Compression do
            xml.mix :compressionScheme, metadata.compression
          end
        end

        xml.mix :BasicImageInformation do
          xml.mix :BasicImageCharacteristics do
            xml.mix :imageWidth, metadata.image_width
            xml.mix :imageHeight, metadata.image_length
            xml.mix :PhotometricInterpretation do
              xml.mix :colorSpace, metadata.color_space
            end
          end

          xml.mix :ImageAssessmentMetadata do
            xml.mix :SpacialMetrics do
              xml.mix :samplingFrequencyUnit, unit
              xml.mix :xSamplingFrequency do
                xml.mix :numerator, metadata.x_resolution
                xml.mix :denominator, 1
              end
              xml.mix :ySamplingFrequency do
                xml.mix :numerator, metadata.y_resolution
                xml.mix :denominator, 1
              end
            end

            xml.mix :ImageColorEncoding do
              xml.mix :BitsPerSample do
                # Handle space-separated bits per sample (e.g., "8 8 8")
                bits = metadata.bits_per_sample.to_s.split(' ')
                samples_per_pixel = metadata.samples_per_pixel.to_i
                
                samples_per_pixel.times do |i|
                  xml.mix :bitsPerSampleValue, bits[i]
                end
                xml.mix :samples_per_pixel, samples_per_pixel
              end
            end
          end
        end
      end

      File.open(File.join(resource_path, md_filename), "w") do |f|
        f.write(xml.target!)
      end
      md_filename

    end
    
    def generate_techmd_text(resource_path, asset_path, asset_filename, md_filename)
      # Initialize Builder
      xml = Builder::XmlMarkup.new(indent: 2)

      xml.textmd :textMD, "xmlns:textmd" => "info:lc/xmlns/textMD-v3" do
        xml.textmd :character_info do
          xml.textmd :charset, "UTF-8"
          xml.textmd :byte_order, "little"
          xml.textmd :byte_size, 8
          xml.textmd :character_size, "variable", encoding: "UTF-8"
          xml.textmd :linebreak, "LF"
        end
      end

      File.open(File.join(resource_path, md_filename), "w") do |f|
        f.write(xml.target!)
      end
      md_filename

    end    
  end
end