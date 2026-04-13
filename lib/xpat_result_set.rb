# frozen_string_literal: true
# XPatResultSet - Ruby translation of Perl XPatResultSet
# Copyright 2000-5, The Regents of The University of Michigan, All Rights Reserved

require_relative 'xpat_result'
require_relative 'dlps_utils'

class XPatResultSet
  attr_reader :name

  def initialize(name)
    @name = name
    @iterator = nil
    @iterator_index = 0
    @iterator_initialized = false
    @stats = {}
    @setsearches = {}
  end

  def clear_results
    initialize(@name)
  end

  def add_result_object(xro)
    type = xro.get_type
    label = xro.get_label
    xpat = xro.get_xpat_object
    dd = xpat.respond_to?(:get_data_dict_name) ? xpat.get_data_dict_name('truncate') : nil

    case type
    when 'SSize'
      num = xro.get_ssize_result
      if label =~ /hitssearch/
        add_hits(num, dd)
      elsif label =~ /recordssearch/
        add_records(num, dd)
      elsif label =~ /detailhitsinitemsearch/
        add_item_hits(num, dd)
      end
    when 'Error'
      # do nothing
    else
      not_byte_mode = !xro.get_byte_mode
      hit_info = xro.get_results_as_array
      add_result_count(hit_info.size, dd)
      hit_info.each do |hit|
        start = not_byte_mode ? hit[0] : hit
        raw = not_byte_mode ? hit[1] : nil
        rawsize = not_byte_mode ? hit[2] : nil
        @setsearches[start] = {
          start: start,
          raw: raw,
          rawsize: rawsize,
          label: label,
          type: not_byte_mode ? "#{type} Raw" : 'byte',
          xpat: xpat
        }
      end
    end
  end

  def clone
    c = self.class.new(@name)
    c.instance_variable_set(:@iterator, @iterator)
    c.instance_variable_set(:@iterator_index, 0)
    c.instance_variable_set(:@iterator_initialized, @iterator_initialized)
    c.instance_variable_set(:@stats, @stats.dup)
    c.instance_variable_set(:@setsearches, @setsearches.dup)
    c
  end

  def init_iterator
    @iterator_index = 0
    return if @iterator_initialized
    @iterator = @setsearches.keys.map do |start|
      s = @setsearches[start]
      [s[:label], s[:raw], start, s[:xpat]]
    end.sort_by { |item| item[2] }
    @iterator_initialized = true
  end

  def get_results_as_array
    raise 'Result iterator not initialized' unless @iterator_initialized
    @iterator
  end

  def get_next_result
    return [nil, nil, nil, nil] if @iterator_index >= @iterator.size
    item = @iterator[@iterator_index]
    @iterator_index += 1
    item
  end

  def get_result_at_index(idx)
    return [nil, nil, nil, nil] if idx >= @iterator.size
    @iterator[idx]
  end

  def sniff_next_result
    return nil if @iterator_index >= @iterator.size
    @iterator[@iterator_index][0]
  end

  def get_next_labeled_result(label)
    (@iterator_index...@iterator.size).each do |i|
      item = get_result_at_index(i)
      return [item[1], item[2], item[3]] if item[0] =~ /#{label}/
    end
    raise "Label=\"#{label}\" not found in RSET"
  end

  def get_all_next_labeled_results(label)
    results = []
    (@iterator_index...@iterator.size).each do |i|
      item = get_result_at_index(i)
      results << [item[1], item[2], item[3]] if item[0] =~ /#{label}/
    end
    raise "Label=\"#{label}\" not found in RSET" if results.empty?
    results
  end

  def get_hits(dd)
    @stats.dig(:dds, dd, :hits)
  end

  def get_item_hits
    @stats.dig(:itemhits)
  end

  def get_records(dd)
    rec = @stats.dig(:dds, dd, :records)
    raise 'Invalid call to XPatResultSet#get_records; records not defined' if rec.nil?
    rec
  end

  def get_result_count(dd)
    rc = @stats.dig(:dds, dd, :resultcount)
    raise 'Invalid call to XPatResultSet#get_result_count; resultCount not defined' if rc.nil?
    rc
  end

  def get_hits_total
    @stats[:totalhits]
  end

  def get_records_total
    @stats[:totalrecords]
  end

  private

  def add_hits(results, dd)
    @stats[:dds] ||= {}
    @stats[:dds][dd] ||= {}
    @stats[:dds][dd][:hits] = results
    @stats[:totalhits] ||= 0
    @stats[:totalhits] += results.to_i
  end

  def add_records(results, dd)
    @stats[:dds] ||= {}
    @stats[:dds][dd] ||= {}
    @stats[:dds][dd][:records] = results
    @stats[:totalrecords] ||= 0
    @stats[:totalrecords] += results.to_i
  end

  def add_result_count(count, dd)
    @stats[:dds] ||= {}
    @stats[:dds][dd] ||= {}
    @stats[:dds][dd][:resultcount] = count
  end

  def add_item_hits(results, _dd)
    @stats[:itemhits] = results
  end
end
