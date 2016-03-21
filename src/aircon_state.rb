# coding: utf-8
require 'rubygems'
require 'bundler/setup'

class AirconState
  attr_reader :room
  attr_reader :command_type
  attr_reader :message_type
  attr_reader :level
  attr_reader :temperature
  attr_reader :message

  def initialize(room, level = 0, temperature = 16, command_type = :query, message_type = :request)
    raise 'Invalid temperature, must be between 16 and 25' unless (16 <= temperature and temperature <= 25)
    raise 'Invalid level, must be between 0 and 23' unless (0 <= level and level <= 3)

    @room = room
    @command_type = command_type
    @message_type = message_type
    @level = level
    @temperature = temperature

    data1 =
      case @command_type
      when :command then 0x0c
      when :query   then 0x0d
      else 0x0c
      end

    data2 =
      case @message_type
      when :request  then 0b00000000
      when :response then 0b10000000
      else 0x00
      end

    data2 |= (@level << 4) & 0b00110000
    data2 |= (@temperature - 16) & 0b00001111

    @message =
      Message.new(tag: 0xf5,
                  address: @room,
                  data1: data1,
                  data2: data2)
  end

  def self.of_message(message)
    if message.valid? and message.tag == 0xf5
      room = message.address

      command_type =
        case message.data1
        when 0x0c then :command
        when 0x0d then :query
        else :unknown
        end

      message_type =
        if (message.data2 & 0b10000000) == 0x00 then
          :request
        else
          :response
        end

      level = (message.data2 & 0b00110000) >> 4
      temperature = (message.data2 & 0b00001111) + 16

      self.new(room, level, temperature, command_type, message_type)
    else
      nil
    end
  end

  def query?
    @command_type == :query && @message_type == :request
  end

  def to_binary_s
    @message.to_binary_s
  end

  def to_s
    if query?
      "#{room} query (off)"
    else
      "#{room} #{command_type} #{message_type} level #{level}, #{temperature}°C"
    end
  end
end
