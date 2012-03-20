#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__) + '/..'
require 'lib/manager'

if Object.const_defined(:Encoding)
  Encoding.default_external = 'UTF-8'
  Encoding.default_internal = 'UTF-8'
end

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
    Signal.trap('HUP')  { tune_to_file }
    Signal.trap('INT')  { abort_fetch }
    Signal.trap('USR1') { show_status }

    @lastfm.connect
    tune_to_file
    @player.connect

    loop { sleep }
  end

  def tune_to_file
    station = File.open(@station_file, &:readline).chomp
    if station != @station
      puts "Tuning to #{station.inspect} ..."
      @lastfm.tune_to(station)
      @manager.pending.clear
      puts "Tuned."
    else
      puts "Already tuned to #{station.inspect}."
    end
  end

  def show_status
    lists = [
      ['<<',  $m.playlist.last(10)],
      ['##', [$m.fetching]],
      ['>>',  $m.pending],
    ]

    for prefix, list in lists do
      for e in list do
        next if e.nil? # $m.fetching nil
        percent = sprintf('%3d%%', e.percent_done)
        puts "#{prefix} #{percent}: #{e.track.artist} -- #{e.track.title}"
      end
    end
    puts "-- Time remaining:  #{$p.time_remaining} seconds"
  end

  def abort_fetch
    if $m.fetching then
      track = $m.fetching.track
      puts "Aborting download:  #{track.artist} -- #{track.title}"
      $m.fetching.abort_fetch
    else
      puts 'No download in progress.'
    end
  end
end

CachefmService.new(ARGV.first).run
