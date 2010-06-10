#!/usr/bin/ruby

require 'lib/manager'

# This whole script is just a hack to use with irb.
# It's not really meant to be a final UI, and it
# won't do anything if you run it normally.

def login_info
  # Uncomment and replace with your details if you don't use shell-fm.
  #return ['username', 'md5 of password']

  return shellfm_login_info
end

def play(uri)
  if @play_done then
    $l.tune_to(uri)
    $m.pending.clear
    $m.fetching.abort_fetch if $m.fetching
    return
  else
    $l = LastFM.connect(*login_info)
    $l.tune_to(uri)
  end

  $p = Player.create
  $m = Manager.new($l, $p)

  $p.connect
  @play_done = true
end

def status
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

def abort
  if $m.fetching then
    track = $m.fetching.track
    puts "Aborting download:  #{track.artist} -- #{track.title}"
    $m.fetching.abort_fetch
  else
    puts 'No download in progress.'
  end
end

def shellfm_login_info
  config = Hash.new
  File.open("#{ENV['HOME']}/.shell-fm/shell-fm.rc") do |fh|
    for line in fh do
      next if line =~ /^#/

      name, value = line.chomp.split('=', 2).collect {|s| s.strip}
      config[name] = value
    end
  end

  for key in ['username', 'password'] do
    raise "Cannot determine #{key} from shell-fm.rc" if config[key].nil?
  end

  username = config['username']
  password = Digest::MD5.hexdigest(config['password'])

  return [username, password]
end
