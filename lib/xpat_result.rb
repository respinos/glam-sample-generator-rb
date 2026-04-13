# frozen_string_literal: true
# XPatResult - Ruby translation of Perl XPatResult
# Copyright 2000-5, The Regents of The University of Michigan, All Rights Reserved

require_relative 'dlps_utils'

class XPatResult
  attr_reader :type, :label, :xpat, :mode

  def initialize(result_string, label, xpat, bytemode = nil)
    @type = nil
    @label = label
    @xpat = xpat
    @mode = bytemode
    @results = parse_result(result_string, bytemode)
    @iterator = nil
    @iterator_index = 0
  end

  def get_results_as_array
    @results
  end

  def get_label
    @label
  end

  def get_type
    @type
  end

  def get_byte_mode
    @mode
  end

  def get_xpat_object
    @xpat
  end

  def get_ssize_result
    return nil unless get_type == 'SSize'
    arr = get_results_as_array
    arr[0][1] if arr && arr[0]
  end

  def init_iterator
    @iterator = @results
    @iterator_index = 0
  end

  def get_next_result(key = 'all')
    return nil unless @iterator
    return nil if @iterator_index >= @iterator.size
    hit = @iterator[@iterator_index]
    @iterator_index += 1
    case key
    when 'all' then hit
    when 'byte' then hit[0]
    when 'result' then hit[1]
    when 'rawsize' then hit[2]
    else nil
    end
  end

  private

  def parse_result(result_string, bytemode)
    # Simplified parsing logic for demonstration
    if result_string =~ /<Error>/
      @type = 'Error'
      result_string.scan(/<Error>(.*?)<\/Error>/m).map { |e| e[0] }
    else
      @type = result_string[/<(\w+)>/, 1]
      if bytemode
        starts = result_string.scan(/<Start>(.*?)<\/Start>/m).map { |s| s[0].to_i }
        starts
      else
        arr = result_string.scan(/<Start>(.*?)<\/Start>.*?<Raw><Size>(.*?)<\/Size>(.*?)<\/Raw>/m)
        arr.map { |start, size, raw| [start.to_i, raw, size.to_i] }
      end
    end
  end
end
