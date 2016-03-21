# coding: utf-8
require 'rubygems'
require 'bundler/setup'

require 'bindata'

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
