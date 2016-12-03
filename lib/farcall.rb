
require 'farcall/version'
require 'farcall/transport'
require 'farcall/json_transport'
require 'farcall/endpoint'
begin
  require 'boss-protocol'
  require 'farcall/boss_transport'
rescue LoadError
end
begin
require 'farcall/wsclient_transport'
require 'farcall/em_wsserver_endpoint'
rescue LoadError
  $!.to_s =~ /em-websocket/ or raise
end

  

module Farcall
  # Your code goes here...
end
