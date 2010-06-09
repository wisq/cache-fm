require 'dl'

module ID3
  class API; class << self
    SYMBOLS = [
      [:id3_file_fdopen, 'PII'],
      [:id3_file_close,  'IP'],
      [:id3_file_tag,    'PP'],
    ]

    def init
      return if @symbols

      dl = DL.dlopen('/usr/lib/libid3tag.so')

      syms = {}
      for key, type in SYMBOLS do
        syms[key] = dl.sym(key.to_s, type)
      end

      @symbols = syms
    end

    private
    def call(key, *args)
      r, rs = call_raw(key, *args)
      return r
    end

    def call_raw(key, *args)
      sym = @symbols[key]
      raise "Symbol not found: #{key}" if sym.nil?
      return sym.call(*args)
    end

    public
    def file_fdopen(fd, write)
      mode = if write then 1 else 0 end
      return call(:id3_file_fdopen, fd.to_i, mode)
    end

    def file_close(file)
      return call(:id3_file_close, file)
    end

    def file_tag(file)
      return call(:id3_file_tag, file)
    end
  end; end

  class File
    attr_reader :tag

    def initialize(path, write = false)
      API.init

      mode = if write then 'r+' else 'r' end
      @fd   = ::File.new(path, mode)
      @file = API.file_fdopen(@fd, write)

      id3  = API.file_tag(@file)
      @tag = Tag.new(id3)
    end

    def close
      API.file_close(@file)
      begin
        @fd.close
      rescue Errno::EBADF
      end
    end
  end

  class Tag
    def initialize(tag)
      @tag = tag
    end
  end
end
