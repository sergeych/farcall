require 'farcall'
begin
  require 'websocket-client-simple'
  require_relative './monitor_lock'
  require 'json'

  module Farcall
    # Websocket client transport using JSON encodeing. Works with ruby threads, pure ruby, runs
    # everywhere. Use if like any thoer Farcall::Transport, for example:
    #
    # in your Gemfile
    #
    #     gem 'websocket-client-simple'
    #
    # in the code
    #
    #     wst = Farcall::WebsocketJsonClientTransport.new 'ws://icodici.com:8080/test'
    #     i = Farcall::Interface.new transport: wst
    #     result = i.authenticate(login, password) # remote call via interface...
    #
    class WebsocketJsonClientTransport < Farcall::Transport

      # Create transport connected to the specified websocket url. Constructor blocks
      # until connected, or raise error if connection can't be established. Transport uses
      # JSON encodgin over standard websocket protocol.
      def initialize ws_url
        # The stranges bug around in the WebSocket::Client (actually in his eventemitter)
        super()
        me = self

        is_open = Semaphore.new
        @ws     = WebSocket::Client::Simple.connect(ws_url)

        @ws.on(:open) {
          # if me != self
          #   puts "\n\n\nSelf is set to wrong in the callback in #{RUBY_VERSION}\n\n\n"
          # end
          # puts "client is open"
          is_open.set
        }

        @ws.on(:message) { |m|
          me.push_input JSON.parse(m.data)
        }
        @ws.on(:close) { close }
        is_open.wait_set
      end

      # :nodoc:
      def send_data data
        @ws.send JSON[data]
      end

    end

  end
rescue LoadError
  $!.to_s =~ /websocket/ or raise
end
