# frozen_string_literal: false
require 'sequel'

class Collection

  attr_accessor :config, :admin_map, :xcoll_map, :ic_id, :ic_vi, :reverse_ic_vi

  def initialize(collid)
    @collid = collid
    @userid = ENV['DLPS_DEV'] || 'dlxsadm'
    @config = $db[:Collection]
      .join(:ImageClass, :collid => :collid, :userid => :userid)
      .where(Sequel.lit('Collection.collid = ? AND Collection.userid = ?', collid, @userid)).first
    @admin_map = _field2map(@config[:field_admin_maps])
    @xcoll_map = _field2map(@config[:field_xcoll_maps])

    ic_id = @admin_map['ic_id'].first[0].downcase

    # find the identifier in the source data
    @ic_id = nil
    @reverse_load_map = {}
    load_map = _field2map(@config[:field_load_maps])
    load_map.keys.each do |key|
      if load_map[key].has_key?(ic_id)
        @ic_id = key
      end
    end
    if @ic_id.nil?
      @ic_id = ic_id
    end
    load_map.keys.each do |key|
      load_map[key].keys.each do |key2|
        @reverse_load_map[key2] = key
      end
    end

    @ic_vi = @admin_map['ic_vi'] || {}
    @reverse_ic_vi = {}
    if not @ic_vi.empty?
      @reverse_ic_vi = {}
      @ic_vi[@admin_map['ic_fn'].first[0].downcase] = 1
    end
    STDERR.puts "IC_VI = #{@ic_vi}"
    @ic_vi.keys.each do |key|
      key2 = @reverse_load_map[key]
      if @reverse_ic_vi[key2].nil?
        @reverse_ic_vi[key2] = []
      end
      @reverse_ic_vi[key2] << key
    end

    if @xcoll_map["dc_ri"].nil? and ! @xcoll_map["dlxs_ri"].nil?
      @xcoll_map["dc_ri"] = @xcoll_map["dlxs_ri"]
    end
    if @xcoll_map["dc_ti"].nil? and ! @xcoll_map["dlxs_ma"].nil?
      @xcoll_map["dc_ti"] = @xcoll_map["dlxs_ma"]
    end

  end

  private
    def _field2map(s)
      mapping = {}
      if s.nil?
        return mapping
      end
      lines = s.split("|")
      lines.each do |line|
        if not line.empty?
          key, original_values = line.split(':::')
          key.downcase!
          values = original_values.downcase
          mapping[key] = {}
          if values.nil?
            mapping[key][key] = 1
          elsif values[0] == '"'
            mapping[key]['_'] = original_values
          else
            values.split(' ').each do |value|
              mapping[key][value.downcase] = 1
            end
          end
        end
      end
      mapping
    end

end
