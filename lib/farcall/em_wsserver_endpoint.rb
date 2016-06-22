begin
  require 'em-websocket'
  require 'eventmachine'
  require_relative './em_farcall'

  module EmFarcall

    # Farcall websocket client. To use it you must add
    #
    #   gem 'websocket-client-simple'
    #
    # to your Gemfile or somehow else install this gem prior to require 'em_farcall' and
    # constructing its instances. We do not include it into gem dependencies as it uses EventMachine
    # which is not needed under JRuby and weight alot.
    #
    class WsServerEndpoint < EmFarcall::Endpoint

      # Create endpoint with the already opened websocket instance. Note that all the handshake
      # should be done prior to construct endpoint (e.g. you may want to have different endpoints
      # for different paths and arguments)
      #
      # @param [EM::WebSocket] websocket socket in open state (handshake should be passed)
      def initialize websocket, **kwargs
        @input  = EM::Channel.new
        @output = EM::Channel.new
        super(@input, @output, **kwargs)

        websocket.onmessage { |data|
          @input << unpack(data)
        }
        @output.subscribe { |data|
          websocket.send(pack data)
        }
      end

      def unpack data
        JSON.parse data
      end

      def pack data
        JSON[data]
      end

    end

  end
rescue LoadError
  $!.to_s =~ /em-websocket/ or raise
end

