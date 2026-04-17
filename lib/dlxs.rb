# frozen_string_literal: false

require 'cgi'
require 'pp'

DC_MAP = {}
DC_MAP["dc_ri"] = "dc.rights"
DC_MAP["dc_ti"] = "dc.title"
DC_MAP["dc_cr"] = "dc.creator"
DC_MAP["dc_su"] = "dc.subject"
DC_MAP["dc_de"] = "dc.description"
DC_MAP["dc_so"] = "dc.source"
DC_MAP["dc_fo"] = "dc.format"
DC_MAP["dc_da"] = "dc.date"
DC_MAP["dc_id"] = "dc.identifier"
DC_MAP["dc_rel"] = "dc.relation"
DC_MAP["dc_type"] = "dc.type"
DC_MAP["dc_la"] = "dc.language"
DC_MAP["dc_cov"] = "dc.coverage"
DC_MAP["dc_gen"] = "dc.genre"  

module DLXS

  class Record

    attr_reader :m_id, :m_iid, :m_fn, :data

    def initialize(data)
      @data = {}
      data.each do |k, v|
        @data[k] = CGI.unescapeHTML(v).split('|||') if v.is_a?(String)
      end
      @m_id = data[:m_id].downcase
      @m_iid = data[:m_iid].downcase
      @m_fn = data[:m_fn].downcase
      @has_media = data[:istruct_ms] == 'P'
    end

    def has_media?
      @has_media
    end

    def has_plaintext?(fields)
      !plaintext(fields).empty?
    end

    def plaintext(fields)
      value = []
      fields.each do |fld|
        value << @data[fld.to_sym] unless @data[fld.to_sym].nil? || @data[fld.to_sym].empty?
      end
      value.flatten
    end

    def service_metadata(xcoll_map)
      datum = {}
      xcoll_map.each do |k, v|
        next unless k.start_with?("dc_")
        next if k == "dc_ri"
        value = []
        v.each do |fld, _|
          # value << @data[fld.to_sym].split('|||') unless ( @data[fld.to_sym].nil? || (@data[fld.to_sym].is_a?(String) && @data[fld.to_sym].empty?) )
          value << @data[fld.to_sym] unless @data[fld.to_sym].nil? || @data[fld.to_sym].empty?
        end
        dc_k = DC_MAP[k]
        datum[dc_k] = [value] unless value.empty?
        datum[dc_k].flatten! if datum[dc_k].is_a?(Array)
      end
      datum
    end

    def metadata
      @data
      # datum = {}
      # @data.each do |k, v|
      #   datum[k] = [v]
      # end
      # datum

    end

    def rights_statement(xcoll_map)
      if xcoll_map["dc_ri"]["_"].nil?
          value = []
          xcoll_map["dc_ri"].keys.each do |fld|
            value << @data[fld.to_sym] unless @data[fld.to_sym].nil?
          end
          value.flatten
        else
          [ xcoll_map["dc_ri"]["_"][1..-2] ]
        end
    end
  end

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

  class Collection::TextClass
    attr_accessor :config, :collid

    def initialize(collid)
      @collid = collid
      @userid = ENV['DLPS_DEV'] || 'dlxsadm'
      @config = $db[:Collection]
        .join(:TextClass, :collid => :collid, :userid => :userid)
        .where(Sequel.lit('Collection.collid = ? AND Collection.userid = ?', collid, @userid)).first
    end

    def dd_path()
      @config[:dd].split('|').map do |dd_path|
        "/quod/idx/#{@collid[0]}/#{@collid}/#{@collid}.dd"
      end
    end


  end

end