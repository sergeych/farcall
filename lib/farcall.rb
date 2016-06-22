
require 'farcall/version'
require 'farcall/transport'
require 'farcall/json_transport'
require 'farcall/endpoint'
begin
  require 'boss-protocol'
  require 'farcall/boss_transport'
rescue LoadError
end
require 'farcall/wsclient_transport'
require 'farcall/em_wsserver_endpoint'


module Farcall
  # Your code goes here...
end
