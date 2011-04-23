require 'lib/player'
require 'lib/lastfm'

# ID3 tagging:
require 'mp3info'

# Banlists:
require 'yaml'

class Manager
  CACHE_DIR = ENV['HOME'] + '/.cache-fm/cache'
  BANNED_FILE = 'banned.yml'

  class Entry
    attr_reader :track, :player_id

    def initialize(track)
      @track = track
      @done  = File.exists?(cache_file)
    end

    def done?
      return @done
    end

    def percent_done
      return 100 if done?
      return 0 if @bytes_total.nil?
      return 100 * @bytes_done / @bytes_total
    end

    def fetch
      file = cache_file
      # FIXME: Stop tagging already-downloaded files
      #        once we settle out the ID3 tagging issue.
      return tag(file) if done?

      temp = file + '.tmp'
      success = false
      begin
        File.open(temp, 'w') do |fh|
          track.fetch do |res|
            @bytes_done  = 0
            @bytes_total = res['content-length'].to_i

            res.read_body do |chunk|
              @bytes_done += chunk.length
              fh.write(chunk)

              return false if @abort
            end
          end

          if @bytes_done != @bytes_total then
            raise "Truncated download: #{@bytes_done} versus #{@bytes_total}"
          end
        end

        if File.stat(temp).size != @bytes_total then
          raise "File size mismatch: #{stat.size} versus #{@bytes_total}"
        end

        success = true
      rescue LastFM::HTTPError => e
        puts "Download failed: #{e.message}"
      rescue Exception => e # intentionally broad
        puts "Download failed: #{e.inspect}"
      end

      if success then
        tag(temp)
        File.rename(temp, file)
        return @done = true
      end

      begin
        unlink(temp)
      rescue Exception => e # intentionally broad
        # ignore
      end
      return false
    end

    def add(player)
      @player_id = player.add(player_file)
    end

    def abort_fetch
      @abort = true
    end

    private
    def cache_file
      return "#{CACHE_DIR}/#{@track.id}.mp3"
    end
    def player_file
      return "#{@track.id}.mp3"
    end

    def tag(file)
      Mp3Info.open(file, :encoding => 'utf-8') do |mp3|
        mp3.removetag1
        mp3.tag2.TPE1 = @track.artist
        mp3.tag2.TALB = @track.album
        mp3.tag2.TIT2 = @track.title
      end
    end
  end

  attr_reader :playlist, :fetching, :pending
  attr_accessor :banned

  def initialize(lastfm, player)
    @banned = []
    load_banned if File.exists?(BANNED_FILE)

    @lastfm = lastfm
    @player = player
    @download = false

    @playlist = Array.new
    @pending  = Array.new

    @download_thread = Thread.new do
      loop do
        download_loop
      end
    end

    @player.subscribe(Player::EVENT_REMAIN, self.method('event_remain'))
  end

  def load_banned
    @banned = YAML.load_file(BANNED_FILE)
    puts "Loaded #{@banned.count} banned patterns."
  end

  private
  def download_loop
    sleep unless @download

    playlist = nil
    begin
      playlist = @lastfm.playlist
    rescue LastFM::HTTPError => e
      puts "Playlist download failed: #{e.message}"
      sleep(3)
      return
    end

    puts "New playlist downloaded."
    for track in playlist.tracks do
      ent = Entry.new(track)
      # Uncomment for "offline mode", or for rapidly tagging your cache.
      #next unless ent.done?
      @pending << ent
    end

    until @pending.empty? do
      @fetching = entry = @pending.shift

      title = "#{entry.track.artist} -- #{entry.track.title}"

      if is_banned?(entry.track) then
        puts "Banned:      #{title}"
        next
      elsif entry.done? then
        puts "From cache:  #{title}"
      else
        puts "Fetching:    #{title}"
      end

      begin
        entry.fetch
      rescue Errno::EINTR
        # FIXME: Find a better way to detect this.
        puts "Download timed out."
      end

      if entry.done? then
        entry.add(@player)
        @playlist << entry
      end

      @fetching = nil
    end

    puts "Done with current playlist."

    # Throttle playlist fetches, and give callbacks
    # a chance to stop the downloading.
    sleep(3)
  end

  def event_remain(time)
    old = @download
    new = time < 3600
    # Uncomment to keep fetching indefinitely.
    # When combined with the "offline mode" uncomment,
    #   will continually retag a library until stopped.
    #new = true

    if new != old then
      verb = if new then 'started' else 'stopped' end
      puts "Buffer at #{time} seconds remaining, download #{verb}."

      @download = new
      @download_thread.wakeup if @download
    end
  end

  private

  def is_banned?(track)
    @banned.any? do |entry|
      entry.all? do |field, match|
        match === track.send(field)
      end
    end
  end
end
