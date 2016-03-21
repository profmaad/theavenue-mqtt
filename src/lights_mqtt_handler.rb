# coding: utf-8
require 'rubygems'
require 'bundler/setup'

require 'eventmachine'
require 'em/mqtt'

class LightsMQTTHandler
  def initialize(config, commands)
    @retain = config['mqtt']['retain'] || true

    @prefix = config['mqtt']['prefix'] || ''
    @prefix += '/' unless @prefix.end_with? '/'

    @rooms = config['lights']

    @connection = EventMachine::MQTT::ClientConnection.connect(config['mqtt']['broker'])
    @commands = commands

    @topics = @rooms.flat_map do |room_id, ids|
      room_name = ids['name']
      ids.reject{|key, _| key == 'name'}.map{|id, name| [topic(room_name, name, "brightness/set"), [room_id, id]]}
    end.to_h

    @last_value = @topics.map {|key,_| [key,0]}.to_h

    @connection.receive_callback do |message|
      puts "Received MQTT message: #{message.inspect} (#{message.payload.to_i})"
      room, id = @topics[message.topic]

      if room and id
        brightness = case message.payload
                     when 'on'
                       if @last_value[message.topic] == 0 then 50 else @last_value[message.topic] end
                     when 'off'
                       0
                     else
                       message.payload.to_i
                     end

        @last_value[message.topic] = brightness unless (brightness.nil? or brightness == 0)

        @commands.push(LightState.new(room, id, brightness).to_binary_s) unless brightness.nil?
      else
        puts "Received lights MQTT message for unexpected topic: #{message.inspect}"
      end
    end

    @topics.each_key {|topic| @connection.subscribe topic}
  end

  def post_init
    'Lights publisher initialized'
  end

  def unbind
    'Lights publisher terminated'
  end

  def topic(room, id, suffix)
    "#{@prefix}lights/#{room}/#{id}/#{suffix}"
  end

  def publish(state)
    return if state.query?

    room_config = @rooms[state.room] || {}
    room = room_config['name'] || state.room.to_s
    id = room_config[state.id] || state.id.to_s

    light_state = if state.brightness == 0 then 'off' else 'on' end

    @connection.publish(topic(room, id, "brightness"), state.brightness, @retain)
    @connection.publish(topic(room, id, "state"), light_state, @retain)
  end
end
