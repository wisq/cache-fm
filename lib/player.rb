class Player
  EVENT_STATE  = :state
  EVENT_TIME   = :time
  EVENT_REMAIN = :remain
  EVENTS = [EVENT_STATE, EVENT_TIME, EVENT_REMAIN]

  STATE_PLAYING = :playing
  STATE_PAUSED  = :paused
  STATE_STOPPED = :stopped      # User requested a stop.
  STATE_STARVED = :starved      # Stopped due to no available tracks.
  STATE_WAITING = :waiting      # Command sent, waiting for callback.
  STATE_UNKNOWN = :unknown      # Error / unknown state.

  attr_reader :state

  def self.create
    players = [:MPD, :ITunes]
    players.reverse! if File.exists? '/Applications/iTunes.app'

    players.each do |type|
      require "lib/player/#{type.to_s.downcase}"
      cls = const_get(type)
      return cls.new if cls.available?
    end
    
    raise 'No players available; see README for details'    
  end
    

  def initialize
    @subscribers = Hash.new
    for event in EVENTS do
      @subscribers[event] = Hash.new
    end
    @serial = 1
  end

  def subscribe(event, method)
    id = @serial
    @serial += 1

    @subscribers[event][id] = method
    return id
  end

  def unsubscribe(event, id)
    return @subscribers[event].delete(id)
  end

  private
  def send_event(event, *args)
    for id, method in @subscribers[event] do
      method.call(*args)
    end
  end

  def state=(state)
    @state = state
    send_event(EVENT_STATE, state)
  end
end
