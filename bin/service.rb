#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__) + '/..'
require 'lib/manager'

$stdout.sync = true
$stderr.sync = true

# This is a daemonised version for running
# as a service via e.g. runit.

class CachefmService
  def login_info
    # Set $CACHE_FM_LOGIN to "username:md5-of-password"
    return ENV['CACHE_FM_LOGIN'].split(':')
  end

  def initialize(station_file)
    @station_file = station_file
    @station = nil

    @lastfm  = LastFM::Session.new(*login_info)
    @player  = Player.create
    @manager = Manager.new(@lastfm, @player)
  end

  def run
    Signal.trap('HUP')  { reload }
    Signal.trap('INT')  { abort_fetch }
    Signal.trap('USR1') { show_status }

    @lastfm.connect
    tune_to_file
    @player.connect

    loop { sleep }
  end

  def reload
    @manager.load_banned
    tune_to_file
  end

  def tune_to_file
    station = File.open(@station_file, &:readline).chomp
    if station != @station
      puts "Tuning to #{station.inspect} ..."
      @lastfm.tune_to(station)
      @manager.pending.clear
      puts "Tuned."
      @station = station
    else
      puts "Already tuned to #{station.inspect}."
    end
  end

  def show_status
    lists = [
      ['<<',  @manager.playlist.last(10)],
      ['##', [@manager.fetching]],
      ['>>',  @manager.pending],
    ]

    for prefix, list in lists do
      for e in list do
        next if e.nil? # @manager.fetching nil
        percent = sprintf('%3d%%', e.percent_done)
        puts "#{prefix} #{percent}: #{e.track.artist} -- #{e.track.title}"
      end
    end
    puts "-- Time remaining:  #{@player.time_remaining} seconds"
  end

  def abort_fetch
    if @manager.fetching then
      track = @manager.fetching.track
      puts "Aborting download:  #{track.artist} -- #{track.title}"
      @manager.fetching.abort_fetch
    else
      puts 'No download in progress.'
    end
  end
end

puts "Starting up ..."
begin
  CachefmService.new(ARGV.first).run
ensure
  puts "Shutting down."
end
