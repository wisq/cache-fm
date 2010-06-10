class Player::MPD < Player
  def self.available?
    begin
      require 'rubygems'
      require 'librmpd'
      true
    rescue LoadError
      false
    end
  end
  
  def initialize
    super

    @remain_last = -1
    @remain_current = @remain_future = 0

    @mpd = ::MPD.new

    methods = self.private_methods - Object.private_instance_methods
    for name in methods do
      next unless name =~ /_callback$/

      num = ::MPD.const_get(name.upcase)
      @mpd.register_callback(self.method(name), num)
    end
  end

  def connect
    Thread.abort_on_exception = true
    @mpd.connect(true)

    @state = STATE_WAITING

    calc_remaining
  end

  def add(track)
    file = path_to_track(track)

    # FIXME: This is ugly...
    unless known_files.include? file
      @mpd.update
      sleep(1)
      until known_files(true).include? file
        puts "Waiting for MPD update..."
        sleep(1)
      end
    end
    @mpd.add(file)

    last = @mpd.playlist.last
    raise "Added #{file}, got #{last['file']}" unless file == last['file']

    id = last['id'].to_i
    if @state == STATE_STARVED then
      @mpd.playid(id)
      self.state = STATE_WAITING
    end

    return id
  end

  def jump(id)
    @mpd.playid(id)
  end

  def pause_toggle
    @mpd.pause = !@mpd.paused?
  end

  def stop
    @manual_stop = true
    @mpd.stop
  end

  def time_remaining
    return @remain_current + @remain_future
  end

  private
  def path_to_track(track)
    return track
  end

  def state_callback(name)
    self.state =
      case name.to_sym
      when :play  then STATE_PLAYING
      when :pause then STATE_PAUSED
      when :stop  then
        if @manual_stop then
          @manual_stop = false
          STATE_STOPPED
        else
          @remain_future = @remain_current = 0
          send_remaining
          STATE_STARVED
        end
      else
        puts "Unknown MPD state: #{name}"
        STATE_UNKNOWN
      end
  end

  def time_callback(pos, total)
    return if @state == STATE_WAITING
    @remain_current = (total - pos)
    send_event(EVENT_TIME, pos, total)
    send_remaining
  end

  def playlist_callback(*args)
    calc_remaining
  end
  def current_songid_callback(*args)
    calc_remaining
  end

  def calc_remaining
    remain = 0

    song = @mpd.status['song']
    if song then
      list = @mpd.playlist
      pos  = song.to_i
      for track in list[pos + 1, list.length] do
        len = track['time'].to_i
        # Cap songs at 10 minutes.
        # Hour-long songs aren't worth holding up more songs
        # if you might just end up skipping it anyway!
        len = 600 if len > 600
        remain += len
      end
    end

    @remain_future = remain
    return send_remaining
  end

  def send_remaining
    remain = self.time_remaining
    if remain > @remain_last || remain % 10 == 0 then
      send_event(EVENT_REMAIN, remain)
    end

    @remain_last = remain
    return remain
  end

  def known_files(refresh = false)
    # Slow operation, so we cache it.
    @known_files = @mpd.files if refresh || @known_files.nil?
    return @known_files
  end
end
