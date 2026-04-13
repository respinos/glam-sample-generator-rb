
# QueryFactory - Ruby translation of Perl QueryFactory
# Copyright 2000-2005, The Regents of The University of Michigan, All Rights Reserved

require_relative 'dlps_utils'

class QueryFactory
  attr_reader :namespaces, :mapper, :mappables

  RECOGNIZED_SEARCH_ENGINES = {
    'pat50' => true,
    'ot60' => true
  }

  def initialize(query, mapper, mappable_params = [], default_namespace = 'label')
    @mapper = mapper
    @mappables = mappable_params.map { |k| [k, true] }.to_h
    @namespaces = {}
    ns = %w[label synthetic native].include?(default_namespace) ? default_namespace : 'label'
    if query.is_a?(Hash)
      @namespaces[ns] = query.dup
    elsif query.respond_to?(:params)
      @namespaces[ns] = {}
      query.params.each do |param, values|
        # qN is special, filter out quotes
        if param =~ /^q\d+$/
          values = Array(values).map { |v| v.gsub(/["'`]/, ' ') }
        end
        @namespaces[ns][param] = values.is_a?(Array) && values.size == 1 ? values[0] : values
      end
    else
      raise ArgumentError, 'query must be a Hash or respond to :params'
    end
    update_parameter_namespaces(ns)
    subclass_initialize
  end

  def update_parameter_namespaces(from_namespace)
    to_populate = %w[label synthetic native] - [from_namespace]
    master = @namespaces[from_namespace]
    to_populate.each do |to_ns|
      ref = {}
      master.each do |key, value|
        if is_mappable?(key)
          if value.is_a?(Hash)
            value.each do |item, v|
              mapped = @mapper.map(item, from_namespace, to_ns) if @mapper.respond_to?(:map)
              ref[key] ||= {}
              ref[key][mapped || item] = v
            end
          else
            mapped = @mapper.map(value, from_namespace, to_ns) if @mapper.respond_to?(:map)
            ref[key] = mapped || value
          end
        else
          ref[key] = value.is_a?(Hash) ? value.dup : value
        end
      end
      @namespaces[to_ns] = ref
    end
  end

  def is_mappable?(key)
    @mappables.keys.any? { |m| key =~ /^#{m}$/ }
  end

  def get_qN_names
    native = @namespaces['native']
    native.keys.grep(/^q\d+$/).map { |k| k.sub(/^q/, '').to_i }.sort
  end

  def get_amtN_names
    native = @namespaces['native']
    native.keys.grep(/^amt\d+$/).map { |k| k.sub(/^amt/, '').to_i }.sort
  end

  def get_rgnN_names
    native = @namespaces['native']
    native.keys.grep(/^rgn\d+$/).map { |k| k.sub(/^rgn/, '').to_i }.sort
  end

  def get_opN_names
    native = @namespaces['native']
    native.keys.grep(/^op\d+$/).map { |k| k.sub(/^op/, '').to_i }.sort
  end

  def get_rgn_name
    native = @namespaces['native']
    native.keys.grep(/^rgn$/)
  end

  def base_query(engine = nil)
    discipline = if engine.nil?
      'pat50BaseQuery'
    elsif RECOGNIZED_SEARCH_ENGINES[engine]
      "#{engine}BaseQuery"
    else
      raise ArgumentError, "#{engine} not recognizedSearchEngine!"
    end
    send(discipline)
  end

  # Default implementations for pat50BaseQuery and ot60BaseQuery
  # (Only simple type shown for brevity; extend as needed)
  def pat50BaseQuery
    native = @namespaces['native']
    type = native['type']
    case type
    when 'simple'
      q_params = native.keys.grep(/^q\d+$/).map { |k| k.sub(/^q/, '').to_i }.sort
      rgnN_params = native.keys.grep(/^rgn\d+$/).map { |k| k.sub(/^rgn/, '').to_i }.sort
      rgn_params = native.keys.grep(/^rgn$/)
      q = "q#{q_params[0]}"
      search = if native[q].is_a?(Hash)
        '(' + native[q].keys.map { |term| pat50_truncation_handler(term) }.join(' + ') + ')'
      else
        '(' + pat50_truncation_handler(native[q]) + ')'
      end
      if q_params[0] == rgnN_params[0]
        rgn = "rgn#{rgnN_params[0]}"
        search = "(#{search} within (#{native[rgn]}))"
      end
      if rgn_params[0]
        rgn = 'rgn'
        if !rgnN_params[0]
          search = "(#{search} within (#{native[rgn]}))"
        else
          rgnN = "rgn#{rgnN_params[0]}"
          search = "(#{search} within (#{native[rgn]}))" if native[rgn] != native[rgnN]
        end
      end
      search
    else
      raise NotImplementedError, "pat50BaseQuery for type #{type} not implemented"
    end
  end

  def pat50_truncation_handler(term)
    # Stub: implement stemming logic as needed
    term.to_s
  end

  def subclass_initialize
    # For subclasses to override
  end
end
