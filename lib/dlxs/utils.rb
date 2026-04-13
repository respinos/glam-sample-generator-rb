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
      tif_filename = asset[:basename] + ".tif"
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
        elsif asset_filename.end_with?(".txt") then "~md.textmd.xml"
        else "~md.unknown.xml"
        end
      argv = [ "jhove",
        "-c", "etc/jhove.conf",
        "-h", "xml" ]
      if asset_filename.end_with?(".txt")
        argv << "-m" << "UTF8-hul"
      else
        argv << "-m" << "TIFF-hul"
      end
      argv << asset_filename
      out, status = cmd.run(*argv)
      doc = Nokogiri::XML(out.to_s) { |config| config.default_xml.noblanks }
      jhove_el = if asset_filename.end_with?(".tif")
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
  end
end