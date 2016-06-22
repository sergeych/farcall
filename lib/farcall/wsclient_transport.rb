require 'farcall'
require 'websocket-client-simple'
require_relative './monitor_lock'
require 'json'

module Farcall
  class WebsocketJsonClientTransport < Farcall::Transport

    def initialize ws_url
      # The stranges bug around in the WebSocket::Client (actually in his eventemitter)
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
        # puts "ws client received #{JSON.parse m.data}"
        me.on_data_received and me.on_data_received.call(JSON.parse m.data)
        # puts "and sent"
      }
      @ws.on(:close) { close }
      is_open.wait_set
    end


    def send_data data
      @ws.send JSON[data]
    end

  end
end
