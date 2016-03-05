require 'rubygems'
require 'bundler/setup'

require 'eventmachine'
require 'em/mqtt'
require 'bindata'

class LightState < BinData::Record
  endian :big
  uint8 :tag
  uint8 :room
  uint8 :id
  uint8 :brightness
  uint8 :checksum

  def valid?
    expected = ~((@tag + @room + @id + @brightness) & 0xff) + 1

    expected == checksum
  end
end

class TheAvenueConnection < EventMachine::Connection
  def post_init
    @buffer = ''

    puts 'Connection to The Avenue initialized'
  end

  def unbind
    puts 'Connection to The Avenue terminated'
  end

  def fill_buffer(data)
    remaining = [0, 5 - @buffer.length].max
    @buffer += data.byteslice(0, remaining)
    data = data.byteslice(remaining..-1)

    frame =
      if @buffer.length == 5
        frame = @buffer
        @buffer = ''
        frame
      else
        nil
      end

    frame, data
  end

  def handle_message(message)
    puts message
  end

  def handle_data(data)
    frame, data = fill_buffer(data)

    if not frame.nil?
      state = LightState.read(frame)

      if state.valid?
        handle_message(state)
      else
        # if invalid, check for marker
        # if marker, start buffer there
        if frame.include? '\xfa'
          @buffer = frame.byteslice((frame.index '\xfa')..-1)
        end
      end
    end

    handle_data(data) unless data.empty?
  end

  def receive_data(data)
    handle_data(data)
  end
end
