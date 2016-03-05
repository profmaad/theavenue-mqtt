require 'rubygems'
require 'bundler/setup'

require 'eventmachine'
require 'em/mqtt'
require 'bindata'
require 'yaml'

class Message < BinData::Record
  endian :big
  uint8 :tag
  uint8 :address
  uint8 :data1
  uint8 :data2
  uint8 :checksum, :initial_value => lambda { Message.calculate_checksum(tag, address, data1, data2) }

  def self.calculate_checksum(tag, address, data1, data2)
    sum = tag + address + data1 + data2
    (~(sum & 0xff) + 1) & 0xff
  end

  def valid?
    expected = Message.calculate_checksum(self.tag, self.address, self.data1, self.data2)
    ([0xfa, 0xf5].include? self.tag) and (expected == self.checksum)
  end
end

class LightState
  attr_reader :room
  attr_reader :id
  attr_reader :brightness
  attr_reader :message

  def initialize(room, id = nil, brightness = nil)
    @room = room
    @id = id
    @brightness = brightness

    @message =
      Message.new(tag: 0xfa,
                  address: room,
                  data1: id || 0xff,
                  data2: if brightness.nil? then 0xff else [100 + brightness, 200].min end)
  end

  def self.of_message(message)
    if message.valid? and message.tag == 0xfa
      room = message.address
      id = if message.data1 == 0xff then nil else message.data1 end
      brightness = if message.data2 == 0xff then nil else message.data2 - 100 end

      self.new(room, id, brightness)
    else
      nil
    end
  end

  def query?
    id.nil? or brightness.nil?
  end

  def to_binary_s
    @message.to_binary_s
  end

  def to_s
    if query?
      "#{room} query"
    elsif brightness == 0
      "#{room}.#{id} OFF"
    else
      "#{room}.#{id} ON at #{brightness}%"
    end
  end
end

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

    @connection.receive_callback do |message|
      puts "Received MQTT message: #{message.inspect} (#{message.payload.to_i})"
      room, id = @topics[message.topic]

      if room and id
        @commands.push(LightState.new(room, id, message.payload.to_i).to_binary_s)
      else
        puts "Received MQTT message for unexpected topic: #{message.inspect}"
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

    light_state = if state.brightness == 0 then :off else :on end

    @connection.publish(topic(room, id, "brightness"), state.brightness, @retain)
    @connection.publish(topic(room, id, "state"), light_state, @retain)
  end
end

def to_hex(data)
  data.unpack('H*').first
end

class TheAvenueConnection < EventMachine::Connection
  def initialize(config, publisher, commands)
    @config = config
    @publisher = publisher
    @commands = commands
  end

  def post_init
    @buffer = ''
    @status_timer = EventMachine::PeriodicTimer.new(2) do
      [0x3d, 0x5b, 0x5c, 0x5d].each do |room|
        send_data(LightState.new(room).to_binary_s)
      end
    end

    queue_cb = Proc.new do |command|
      send_data(command)
      @commands.pop &queue_cb
    end
    @commands.pop &queue_cb

    puts 'Connection to The Avenue initialized'
  end

  def unbind
    puts 'Connection to The Avenue terminated'
  end

  def fill_buffer(data)
    remaining = [0, 5 - @buffer.length].max
    @buffer += data.byteslice(0, remaining)
    data = data.byteslice(remaining..-1)

    frame = nil
    if @buffer.length == 5
      frame = @buffer
      @buffer = ''
    end

    [frame, data]
  end

  def dump_buffer(loc)
    puts "BUFFER @#{loc} (#{@buffer.length} bytes): #{to_hex(@buffer)}"
  end

  def handle_message(message)
    light = LightState.of_message(message)
    if not light.nil?
      $stderr.puts "GOT LIGHT STATE: #{light}"
      @publisher.publish(light)
    else
      $stderr.puts "GOT MESSAGE: #{message}"
    end
  end

  def handle_data(data)
    frame, data = fill_buffer(data)

    if not frame.nil?
      state = Message.read(frame)

      if state.valid?
        handle_message(state)
      else
        $stderr.puts 'invalid state, scanning forward'
        # if invalid, check for marker
        # if marker, start buffer there
        @buffer = frame.bytes.drop(1).drop_while {|byte| not (byte == 0xfa)}.pack('C*')
      end
    end

    handle_data(data) unless (data.nil? or data.empty?)
  end

  def receive_data(data)
    $stderr.puts "received data: #{to_hex(data)}"

    handle_data(data)
  end

  def send_data(data)
    $stderr.puts "sending data: #{to_hex(data)}"
    super(data)
  end
end

EventMachine.run do
  config = YAML.load_file(ARGV.shift)

  commands = EventMachine::Queue.new

  lights_mqtt_handler = LightsMQTTHandler.new(config, commands)

  EventMachine.connect(config.dig('theavenue', 'host') || 'localhost', config.dig('theavenue', 'port') || 8080, TheAvenueConnection, config, lights_mqtt_handler, commands)
end
