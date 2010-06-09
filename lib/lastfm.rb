require 'rubygems'

# HTTP support:
#   Base:
require 'net/http'
#   Better escaping:
require 'facets/uri'
#   Date parsing:
require 'time'

# MD5 password hashing:
require 'digest/md5'

# Playlist XML parsing:
require 'rexml/document'

class LastFM
  def new
    raise 'LastFM class cannot be instantiated'
  end

  def self.connect(user, passhash)
    sess = LastFM::Session.new
    sess.username = user
    sess.passhash = passhash
    sess.connect
    return sess
  end

  def self.hash_password(password)
    return Digest::MD5.hexdigest(password)
  end
end

module LastFM::HTTP
  def http_uri(base, params)
    query = params.map do |key, value|
      "#{key}=#{URI.cgi_escape(value)}"
    end.join('&')
    query = "#{base.query}&#{query}" if base.query

    uri = base.dup
    uri.query = query

    return uri
  end

  def http_get(uri, recurse=0, &block)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri.request_uri)

    http.request(request) do |response|
      if response.kind_of? Net::HTTPSuccess then
        yield response
      elsif response.kind_of? Net::HTTPRedirection then
        raise LastFM::HTTPError.new(uri, response) unless recurse > 0

        loc = response['Location']
        newuri = URI.parse(loc)
        http_get(newuri, recurse - 1, &block)
      else
        raise LastFM::HTTPError.new(uri, response)
      end
    end
  end
end

class LastFM::HTTPError < StandardError
  attr_reader :uri, :response

  def initialize(uri, response)
    @uri = uri
    @response = response
  end

  def message
    return "#{@response.code} #{@response.message} accessing #{@uri}"
  end
end

class LastFM::Session
  attr_accessor :username, :passhash

  CONNECT_URL = URI.parse('http://ws.audioscrobbler.com/radio/handshake.php' +
    '?version=0.1&platform=linux&debug=0&language=en').freeze
  ADJUST_URL = URI.parse('http://ws.audioscrobbler.com/radio/adjust.php').freeze
  PLAYLIST_URL = URI.parse('http://ws.audioscrobbler.com/radio/xspf.php').freeze

  include LastFM::HTTP

  def connect
    uri = http_uri(CONNECT_URL,
      'username'    => @username,
      'passwordmd5' => @passhash
    )

    http_get(uri) do |res|
      now = Time.now
      offset = Time.parse(res['Date']) - Time.now

      session, expires = []
      for cookie in res.get_fields('Set-Cookie') do
        name, rest = cookie.split('=', 2)
        next unless name == 'Session'

        session, exp_part, _ = rest.split('; ', 3)
        _, exp_text = exp_part.split('=', 2)
        expires = Time.parse(exp_text)

        break
      end

      unless session.nil?
        @session_id = session
        @session_next = Time.now + 86400
        @session_limit = expires + offset - 300
        return true
      end
    end

    raise 'Unable to acquire LastFM session'
  end

  def tune_to(url)
    status_check

    uri = http_uri(ADJUST_URL,
      'session' => @session_id,
      'url'     => url
    )

    http_get(uri) do |res|
      body = []
      res.read_body do |chunk|
        body << chunk
        break if chunk.include? "\n"
      end

      return true if body.join('') =~ /^response=OK\n/
    end

    raise 'Unable to change LastFM station'
  end

  def playlist
    status_check

    uri = http_uri(PLAYLIST_URL,
      'sk' => @session_id,
      'discovery' => '0',
      'desktop'   => '0'
    )

    for i in 1..5 do
      begin
        http_get(uri) do |res|
          return LastFM::Playlist.new(res.body)
        end
      rescue LastFM::HTTPError => e
        raise e if i == 5
        raise e unless e.response.code.to_i == 503
        p [e.response.code, e.response.message]
        sleep(5)
      end
    end
  end

  private
  def status_check
    raise 'LastFM session not connected' if @session_id.nil?

    # FIXME: When over 'next', failure should be a warning.
    # Failure should always be an error when over 'limit'.
    now = Time.now
    if now > @session_next || now > @session_limit then
      self.connect
    end
  end
end

class LastFM::Playlist
  attr_reader :title, :tracks

  def initialize(body)
    xml = REXML::Document.new(body)
    elems = xml.elements

    elems.each('/playlist/title') do |title|
      @title = title.text
      break
    end

    @tracks = []
    elems.each('/playlist/trackList/track') do |node|
      @tracks << LastFM::Track.new(node)
    end
  end
end

class LastFM::Track
  attr_reader :id, :artist, :album, :title

  include LastFM::HTTP

  def initialize(node)
    data = Hash.new

    node.each_element do |elem|
      next if elem.name == 'link'
      next unless elem.has_text?

      value = elem.text
      data[elem.name] = value
    end

    @id     = data.delete('id').to_i
    @artist = data.delete('creator')
    @album  = data.delete('album')
    @title  = data.delete('title')
    @uri    = URI.parse(data.delete('location'))
  end

  def fetch
    http_get(@uri, 1) do |res|
      yield res
    end
  end
end
