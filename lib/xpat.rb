# frozen_string_literal: false
# XPat - Ruby translation of Perl XPat
# Copyright 2000-5, The Regents of The University of Michigan, All Rights Reserved

require 'open3'
require_relative 'dlps_utils'
require_relative 'search_set'
require_relative 'xpat_result'
require_relative 'xpat_result_set'
require_relative 'remote_connect'

class XPat
  attr_accessor :status, :xpatstatus, :patmode, :dd, :host, :patexec, :port, :psetoffset, :separator, :sgmlfilter, :dataisutf8, :classobject

  def initialize(requesting_host, class_host, class_dd, class_xpat_exec, class_port, pset_offset = nil, defer_xpat = false, class_object = nil)
    @patmode = DlpsUtils.respond_to?(:set_local_or_remote_mode) ? DlpsUtils.set_local_or_remote_mode(requesting_host, class_host) : 'local'
    @dd = class_dd
    @host = class_host
    @patexec = class_xpat_exec
    @port = class_port
    @psetoffset = pset_offset
    @separator = '</Sync>'
    @sgmlfilter = nil
    @dataisutf8 = class_xpat_exec =~ /xpatu/
    @classobject = class_object
    @status = 'OK'
    @xpatstatus = 'XPAT_NOT_SPAWNED'
    spawn_xpat_process('initializationtime') unless defer_xpat
  end

  def set_associated_collid(val)
    @associated_collid = val
  end

  def get_associated_collid
    @associated_collid
  end

  def get_status
    @status
  end

  def get_xpat_status
    @xpatstatus
  end

  def get_mode_cmd_string(mode)
    case mode
    when 'default'
      '{sortorder occur};{quieton raw};'
    when 'bytemode'
      '{sortorder occur};{quieton};'
    when 'bytemode.score'
      '{sortorder asis};{quieton score};'
    else
      raise "Illegal XPat mode: #{mode}"
    end
  end

  def get_data_dict_name(truncate = false)
    truncate ? File.basename(@dd) : @dd
  end

  def get_pset_offset
    @psetoffset
  end

  def define_sgml_filter(filter)
    @sgmlfilter = filter
  end

  # --- Query Methods ---

  def get_results_from_query(label, query, bytemode = nil)
    spawn_xpat_process('querytime') if @xpatstatus == 'XPAT_NOT_SPAWNED'
    return XPatResult.new('<Error>Could not spawn XPAT</Error>', label, self) unless @xpatstatus == 'XPAT_SPAWNED'
    query = query.strip
    query += ';' unless query.end_with?(';')
    default_mode_cmd = get_mode_cmd_string('default')
    byte_mode_cmd = bytemode ? get_mode_cmd_string(bytemode) : ''
    full_query = "#{byte_mode_cmd}#{query}~sync \"EndOfResults\";#{default_mode_cmd}"
    # Character mapping stubbed
    result_string = send_query(full_query)
    XPatResult.new(result_string, label, self, bytemode)
  end

  def get_simple_results_from_query(query, bytemode = nil)
    spawn_xpat_process('querytime') if @xpatstatus == 'XPAT_NOT_SPAWNED'
    return [1, 'Could not spawn XPAT'] unless @xpatstatus == 'XPAT_SPAWNED'
    query = query.strip
    query += ';' unless query.end_with?(';')
    default_mode_cmd = get_mode_cmd_string('default')
    byte_mode_cmd = bytemode ? get_mode_cmd_string(bytemode) : ''
    full_query = "#{byte_mode_cmd}#{query}~sync \"EndOfResults\";#{default_mode_cmd}"
    # TODO: Character mapping if needed
    result_string = send_query(full_query)
    error = nil
    if result_string =~ /<Error>/
      # Collect all error messages
      error_msgs = result_string.scan(/<Error>(.*?)<\/Error>/m).map(&:first).join("\n")
      error = 1
      result_string = error_msgs
    end
    # Remove sync tag
    result_string = result_string.gsub(/<Sync>EndOfResults<\/Sync>/, '')
    [error, result_string]
  end

  def send_command(command)
    return unless @xpatstatus == 'XPAT_SPAWNED'
    return unless @xpat_stdin
    # Ensure at least one semicolon at the end
    command += ';' unless command.end_with?(';')
    command.gsub!(/;+
?\z/, ';')
    @xpat_stdin.puts command
    @xpat_stdin.flush if @xpat_stdin.respond_to?(:flush)
  end

  def get_region_size(search)
    _error, results = get_simple_results_from_query(search, 'bytemode')
    start, ending = results.match(/<Start>(\d+)<\/Start><End>(\d+)<\/End>/)&.captures
    size = ending.to_i - start.to_i if start && ending
    size || 0
  end

  private

  def spawn_xpat_process(spawn_time)
    # Implements process spawning for XPAT (local or remote)
    @xpatstatus = 'XPAT_NOT_SPAWNED'
    @status = 'OK'
    begin
      if @patmode == 'local'
        # Build the XPAT startup command
        startup_command = [@patexec, '-D', @dd, '-q', '-s', 'EndOfResults']
        # Start the process
        @xpat_stdin, @xpat_stdout, @xpat_stderr, @xpat_wait_thr = Open3.popen3(*startup_command)
        # Set autoflush
        @xpat_stdin.sync = true
        # Read initial sync response
        sync_response = ''
        loop do
          chunk = @xpat_stdout.readpartial(4096)
          sync_response << chunk
          break if sync_response.include?(@separator)
        end
        if sync_response.include?('<Sync>EndOfResults</Sync>')
          error_msg = sync_response[/<Error>(.*?)<\/Error>/m, 1]
          if error_msg
            @status = error_msg
            @xpatstatus = 'XPAT_SPAWN_ERROR'
          else
            # Set default mode
            default_mode_cmd = get_mode_cmd_string('default') + '{LeftContext 0};'
            @xpat_stdin.puts default_mode_cmd
            @xpatstatus = 'XPAT_SPAWNED'
          end
        else
          @status = 'No Sync tag sent by XPAT'
          @xpatstatus = 'XPAT_SPAWN_ERROR'
        end
      elsif @patmode == 'remote'
        # Remote mode: use RemoteConnect (stubbed)
        if defined?(RemoteConnect) && RemoteConnect.respond_to?(:open)
          @xpat_stdin, @xpat_stdout = RemoteConnect.open(@host, @port)
        else
          raise 'RemoteConnect.open not implemented'
        end
        @xpat_stdin.sync = true
        remote_verb = @patexec =~ /xpatu/ ? 'XPATU' : 'XPAT'
        startup_command = "#{remote_verb} #{@dd} EndOfResults"
        @xpat_stdin.puts startup_command
        # Read initial sync response
        sync_response = ''
        loop do
          chunk = @xpat_stdout.readpartial(4096)
          sync_response << chunk
          break if sync_response.include?(@separator)
        end
        if sync_response.include?('<Sync>EndOfResults</Sync>')
          error_msg = sync_response[/<Error>(.*?)<\/Error>/m, 1]
          if error_msg
            @status = error_msg
            @xpatstatus = 'XPAT_SPAWN_ERROR'
          else
            default_mode_cmd = get_mode_cmd_string('default') + '{LeftContext 0};'
            @xpat_stdin.puts default_mode_cmd
            @xpatstatus = 'XPAT_SPAWNED'
          end
        else
          @status = 'No Sync tag sent by XPAT (remote)'
          @xpatstatus = 'XPAT_SPAWN_ERROR'
        end
      else
        raise "Unknown patmode: #{@patmode}"
      end
    rescue => e
      @status = "Could not fork XPat process: #{e.message}"
      @xpatstatus = 'XPAT_SPAWN_ERROR'
      raise if spawn_time == 'initializationtime'
    end
  end

  def send_query(query)
    return '' unless @xpat_stdin && @xpat_stdout && @xpatstatus == 'XPAT_SPAWNED'
    @xpat_stdin.puts query
    @xpat_stdin.flush if @xpat_stdin.respond_to?(:flush)
    # Read until separator (</Sync>)
    response = ''
    begin
      loop do
        chunk = @xpat_stdout.readpartial(4096)
        response << chunk
        break if response.include?(@separator)
      end
    rescue EOFError
      # End of file reached
    end
    response
  end
end
