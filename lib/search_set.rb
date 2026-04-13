# frozen_string_literal: true
# SearchSet - Ruby translation of Perl SearchSet
# Copyright 2000-5, The Regents of The University of Michigan, All Rights Reserved

require_relative 'query_factory'

class SearchSet
  attr_reader :name

  def initialize(name)
    @name = name
    @count = 0
    @labels = {}
  end

  def clear_queries
    initialize(@name)
  end

  def add_query(label, query, xpat = nil, mode = nil)
    @count += 1
    @labels[label] = {
      query: query,
      searchname: label,
      count: @count,
      mode: mode,
      xpat: xpat
    }
  end

  def get_search_labels
    @labels.keys.sort_by { |k| @labels[k][:count] }
  end

  def get_query_by_label(label)
    @labels[label] && @labels[label][:query]
  end

  def get_search_name_by_label(label)
    @labels[label] && @labels[label][:searchname]
  end

  def get_xpat_by_label(label)
    @labels[label] && @labels[label][:xpat]
  end

  def get_mode_by_label(label)
    @labels[label] && @labels[label][:mode]
  end
end
