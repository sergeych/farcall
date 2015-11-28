
require 'farcall/version'
require 'farcall/transport'
require 'farcall/json_transport'
require 'farcall/endpoint'
begin
  require 'boss-protocol'
  require 'farcall/boss_transport'
rescue LoadError
end

module Farcall
  # Your code goes here...
end
