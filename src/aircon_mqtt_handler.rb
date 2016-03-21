# coding: utf-8
require 'rubygems'
require 'bundler/setup'

require 'eventmachine'
require 'em/mqtt'

class AirconMQTTHandler
  def initialize(config, commands)
    @retain = config['mqtt']['retain'] || true

    @prefix = config['mqtt']['prefix'] || ''
    @prefix += '/' unless @prefix.end_with? '/'

    @rooms = config['aircon']

    @connection = EventMachine::MQTT::ClientConnection.connect(config['mqtt']['broker'])
    @commands = commands

    @topics = @rooms.map do |room_id, hash|
      room_name = hash['name']
      [topic(room_name, "set"), room_id]
    end.to_h

    @connection.receive_callback do |message|
      puts "Received aircon MQTT message: #{message.inspect} (#{message.payload.to_s})"
      room = @topics[message.topic]

      level, temperature =
             if message.payload.to_s == 'off' then
               [0, 16]
             else
               message.payload.to_s.split(',').map(&:to_i)
             end

      unless
        room.nil? \
        || level.nil? \
        || temperature.nil? \
        || temperature < 16 \
        || temperature > 25 \
        || level < 0 \
        || level > 3 \
      then
        @commands.push(AirconState.new(room, level, temperature, :command).to_binary_s)
      else
        puts "Received MQTT message for unexpected topic: #{message.inspect}"
      end
    end

    @topics.each_key {|topic| @connection.subscribe topic}
  end

  def post_init
    'Aircon publisher initialized'
  end

  def unbind
    'Aircon publisher terminated'
  end

  def topic(room, suffix)
    "#{@prefix}aircon/#{room}/#{suffix}"
  end

  def publish(state)
    return unless state.command_type == :query

    room_config = @rooms[state.room] || {}
    room = room_config['name'] || state.room.to_s

    aircon_state =
      if state.level == 0 then
        'off'
      else
        'on'
      end

    @connection.publish(topic(room, "temperature"), state.temperature, @retain)
    @connection.publish(topic(room, "level"), state.level, @retain)
    @connection.publish(topic(room, "state"), aircon_state, @retain)
  end
end
