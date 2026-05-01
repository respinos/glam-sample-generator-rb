class Cache
  require 'pstore'
  CACHE_PATH = File.join("tmp", "cache")

  def initialize(collid, base_uri)
    @session = HTTP.base_uri(base_uri).persistent
    @cache = PStore.new(File.join(CACHE_PATH, "#{collid}.pstore"))
    yield self if block_given?
  end

  def get(path)
    response = @cache.transaction(true) do
      if @cache.key?(path) and ! @cache[path].empty?
        STDERR.puts "::: #{path}"
        @cache[path]
      else
        nil
      end
    end
    return response unless response.nil?

    response = @cache.transaction do
      response = @session.get(path)
      unless response.success?
        raise "Failed to fetch #{path}: #{response.status}"
      end
      STDERR.puts "<-- #{path}"
      # pp response.headers.to_h
      response = response.to_s
      @cache[path] = response
    end
    response
  end

end
