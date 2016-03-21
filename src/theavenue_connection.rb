# coding: utf-8
require 'rubygems'
require 'bundler/setup'

require 'eventmachine'

def to_hex(data)
  data.unpack('H*').first
end

class TheAvenueConnection < EventMachine::Connection
  def initialize(config, lights_publisher, aircon_publisher, commands)
    @config = config
    @lights_publisher = lights_publisher
    @aircon_publisher = aircon_publisher
    @commands = commands
    @next_query = :lights
  end

  def post_init
    @buffer = ''
    @status_timer = EventMachine::PeriodicTimer.new(5) do
      case @next_query
      when :lights
        [0x3d, 0x5b, 0x5c, 0x5d].each do |room|
          send_data(LightState.new(room).to_binary_s)
        end
        @next_query = :aircon
      else
        [0xa1, 0xa2, 0xa3].each do |room|
          send_data(AirconState.new(room).to_binary_s)
        end
        @next_query = :lights
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
    @status_timer.cancel
    puts 'Connection to The Avenue terminated'
    EventMachine.stop
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
    aircon = AirconState.of_message(message)
    if not light.nil?
      $stderr.puts "GOT LIGHT STATE: #{light}"
      @lights_publisher.publish(light)
    elsif not aircon.nil?
      $stderr.puts "GOT AIRCON STATE: #{aircon}"
      @aircon_publisher.publish(aircon)
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
        @buffer = frame.bytes.drop(1).drop_while {|byte| not (byte == 0xfa || byte == 0xf5)}.pack('C*')
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
