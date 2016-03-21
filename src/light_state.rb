# coding: utf-8
require 'rubygems'
require 'bundler/setup'

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
