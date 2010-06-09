class Player::ITunes < Player
  CACHE_DIR = ENV['HOME'] + '/.cache-fm/cache'

  def self.available?
    begin
      require 'rubygems'
      require 'rbosa'
      true
    rescue LoadError
      false
    end
  end
  
  def initialize
    super

    @itunes = OSA.app('iTunes')
  end

  def connect
    Thread.abort_on_exception = true

    poll_all

    @poller = Thread.new do
      loop do
        sleep 5
        poll_all
      end
    end
  end
  
  def disconnect
    @poller.kill if @poller
    @poller = nil
  end

  def add(track)
    file = path_to_track(track)

    list = lastfm_playlist
    @itunes.add(file, list)

    last = list.file_tracks.to_a.last
    last_size, file_size = [last.location, file].collect { |f| File.stat(f).size }
    raise "Added #{file}, got #{last.location}" unless last_size == file_size

    if @state == STATE_STARVED then
      @itunes.play(last)
      @poller.run
      sleep(0.5)
    end
  end

  def pause_toggle
    @itunes.playpause
  end

  def stop
    @itunes.stop
  end
  
  def time_remaining
    return @remain
  end

  private
  
  def path_to_track(track)
    return "#{CACHE_DIR}/#{track}"
  end

  def playing?
    !@itunes.player_position.nil?
  end
  
  def lastfm_playlist
    library = @itunes.sources.find {|s| s.name == 'Library'}
    library.user_playlists.find {|p| p.name == 'Last.fm'}
  end
  
  def poll_all
    poll_state
    poll_remaining
  end

  def poll_state
    self.state = 
      if !playing? then
        STATE_STARVED
      elsif @itunes.current_playlist.name != 'Last.fm' then
        STATE_UNKNOWN
      else
        case state = @itunes.player_state
        when OSA::ITunes::EPLS::PLAYING then STATE_PLAYING
        when OSA::ITunes::EPLS::PAUSED  then STATE_PAUSED
        when OSA::ITunes::EPLS::STOPPED then STATE_STOPPED
        else
          puts "Unknown iTunes state: #{state.class}"
          STATE_UNKNOWN
        end
      end
  end

  def poll_remaining
    remain = 0
  
    list  = nil
    index = 0
    
    if playing? then
      list = @itunes.current_playlist
      
      if list.name == 'Last.fm' then
        current = @itunes.current_track
        index   = current.index
        remain  = track_length(current) - @itunes.player_position
      else
        list = nil
      end
    end
    
    list ||= lastfm_playlist
    
    for track in list.tracks.drop(index) do
      remain += track_length(track)
    end
  
    @remain = remain
    send_event(EVENT_REMAIN, remain)
  end

  def track_length(track)
    mins, secs = track.time.split(':', 2).map(&:to_i)
    mins * 60 + secs
  end
end