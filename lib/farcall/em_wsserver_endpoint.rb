require 'em-websocket'
require 'eventmachine'
require_relative './em_farcall'

module EmFarcall
  
  # Farcall websocket client, based on the websocket-client-simple gem. We do not put it into
  # dependencies as it is not always needed, so add to your Gemfile first:
  #
  #   gem 'websocket-client-simple'
  #
  # and do not forget to require eventmachine before requiring the farcall. Now you can use it
  # with EM:
  #
  #    require 'eventmachine'
  #    require 'farcall'
  #
  #    # ....
  #
  #    endpoint = nil
  #
  #    EM::WebSocket.run(params) do |ws|
  #      ws.onopen { |handshake|
  #        # Check handshake.path, handshake query
  #        # for example to select the provider, then connect Farcall to websocket:
  #        endpoint = EmFarcall::WsServerEndpoint.new ws, provider: WsProvider.new
  #      }
  #    end
  #
  # now we can use it as usual: remote can call provder method, and we can call remote:
  #
  #    endpoint.remote.do_something( times: 4) { |result|
  #    }
  #
  #
  # We do not include it into gem dependencies as it uses EventMachine
  # which is not needed under JRuby and weight alot (the resto of Farcall plays well with jruby
  # and MRI threads)
  #
  # Due to event-driven nature of eventmachine, WsServerEndpoint uses special version of
  # {EmFarcall::Endpoint} and {EmFarcall::WsProvider} which are code compatible with regular
  # farcall classes except for the callback-style calls where appropriate.
  class WsServerEndpoint < EmFarcall::Endpoint
    
    # Create endpoint with the already opened websocket instance. Note that all the handshake
    # should be done prior to construct endpoint (e.g. you may want to have different endpoints
    # for different paths and arguments)
    #
    # See {EmFarcall::Endpoint} for methods to call remote interface and process remote requests.
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

