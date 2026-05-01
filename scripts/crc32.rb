#!/usr/bin/env ruby

require 'zlib'

def to_xml_id_crc(input_string)
  # Zlib.crc32 returns an unsigned 32-bit integer
  "_#{Zlib.crc32(input_string).to_s(16)}"
end

ARGV.each do |input|
  puts "#{to_xml_id_crc(input)}\t#{input}"
end