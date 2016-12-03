require 'hashie'
require 'eventmachine'
require_relative './promise'

# As the eventmachine callback paradigm is completely different from the threaded paradigm
# of the Farcall, that runs pretty well under JRuby and in multithreaded MRI, we provide
# compatible but different implementations: {EmFarcall::Endpoint}, {EmFarcall::Interface}
# and {EmFarcall::Provider}. Changes to adapt these are minimal except of the callback
# paradigm. The rest is the same.
#
# The eventmachine is not a required dependency, to use EmFarcall place eventmachine _before_
# _requiring_ _farcall:_
#
#     require 'eventmachine'
#     require 'farcall'
module EmFarcall
  
  # Endpoint that run in the reactor thread of the EM. Eventmachine should run by the time of
  # creation of the endpoint. All the methods can be called from any thread, not only
  # EM's reactor thread.
  #
  # As the eventmachine callback paradigm is completely different from the threaded paradigm
  # of the Farcall, that runs pretty well under
  # JRuby and in multithreaded MRI, we provide
  # compatible but different endpoint to run under EM.
  #
  # Its main difference is that there is no sync_call, instead, calling remote commands
  # from the endpoint and/ot interface can provide blocks that are called when the remote
  # is executed.
  #
  # The EM version of the endpoint works with any 2 EM:C:Channels.
  #
  class Endpoint
    
    # Create new endpoint to work with input and output channels
    #
    # @param [EM::Channel] input_channel
    # @param [EM::Channel] output_channel
    def initialize(input_channel, output_channel, errback=nil, provider: nil)
      EM.schedule {
        @input, @output, @errback = input_channel, output_channel, errback
        @trace                    = false
        @in_serial                = @out_serial = 0
        @callbacks                = {}
        @handlers                 = {}
        @unnamed_handler          = -> (name, *args, **kwargs) {
          raise NoMethodError, "method does not exist: #{name}"
        }
        @input.subscribe { |data|
          process_input(data)
        }
        if provider
          @provider         = provider
          provider.endpoint = self
        end
      }
    end
    
    # Set or get provider instance. When provider is set, its public methods are called by the remote
    # and any possible exception are passed back to caller party. You can use any ruby class instance
    # everything will work, operators, indexes[] and like.
    attr_accessor :provider
    
    # Call the remote method with specified name and arguments calling block when done. Returns
    # immediately a {Farcall::Promise} instance which could be used to control remote procedure
    # invocation result asynchronously and effective.
    #
    # Also, if block is provided, it will be called when the remote will be called and possibly
    # return some data. It receives single object paramter with two fields: result.error and
    # result.result. It is also possible to use returned {Farcall::Promise} instance to set
    # multiple callbacks with ease. Promise callbacks are called _after_ the block.
    #
    # `result.error` is not nil when the remote raised error, then `error[:class]` and
    # `error.text` are set accordingly.
    #
    # if error is nil then result.result receives any return data from the remote method.
    #
    # for example:
    #
    #   endpoint.call( 'some_func', 10, 20) { |done|
    #      if done.error
    #        puts "Remote error class: #{done.error[:class]}: #{done.error.text}"
    #      else
    #        puts "Remote returned #{done.result}"
    #   }
    #
    # @param name [String] remote method name
    # @return [Promise] object that call be used to set multiple handlers on success
    #           or fail event. {Farcall::Promise#success} receives remote return result on
    #           success and {Farcall::Promise#fail} receives error object.
    def call(name, *args, **kwargs, &block)
      promise = Farcall::Promise.new
      EM.schedule {
        @callbacks[@in_serial] = -> (result) {
          block.call(result) if block != nil
          if result.error
            promise.set_fail result.error
          else
            promise.set_success result.result
          end
        }
        send_block cmd: name, args: args, kwargs: kwargs
      }
      promise
    end
    
    # Close the endpoint
    def close
      super
    end
    
    # Report error via errback and the endpoint
    def error text
      STDERR.puts "farcall ws server error #{text}"
      EM.schedule {
        @errback.call(text) if @errback
        close
      }
    end
    
    # Set handler to perform the named command. Block will be called when the remote party calls
    # with parameters passed from the remote. The block returned value will be passed back to
    # the caller.
    #
    # If the block raises the exception it will be reported to the caller as an error (depending
    # on it's platofrm, will raise exception on its end or report error)
    def on(name, &block)
      @handlers[name.to_s] = block
    end
    
    # Process remote command. First parameter passed to the block is the method name, the rest
    # are optional arguments of the call:
    #
    #    endpoint.on_command { |name, *args, **kwargs|
    #      if name == 'echo'
    #        { args: args, keyword_args: kwargs }
    #      else
    #        raise "unknown command"
    #      end
    #    }
    #
    # raising exceptions from the block cause farcall error to be returned back th the caller.
    def on_command &block
      raise "unnamed handler should be present" unless block
      @unnamed_handler = block
    end
    
    # Same as #on_command (compatibilty method)
    def on_remote_call &block
      on_command block
    end
    
    # Get the Farcall::RemoteInterface connnected to this endpoint. Any subsequent calls with
    # return the same instance.
    def remote
      @remote ||= EmFarcall::Interface.new endpoint: self
    end
    
    private
    
    # :nodoc: sends block with correct framing
    def send_block **data
      data[:serial] = @out_serial
      @out_serial   += 1
      @output << data
    end
    
    # :nodoc:
    def execute_command cmd, ref, args, kwargs
      kwargs = (kwargs || {}).inject({}) {
          |all, kv|
        all[kv[0].to_sym] = kv[1]
        all
      }
      args << kwargs if kwargs && !kwargs.empty?
      result = if proc = @handlers[cmd.to_s]
                 proc.call(*args)
               elsif @provider
                 provider.send :remote_call, cmd.to_sym, args
               else
                 @unnamed_handler.call(cmd, args)
               end
      send_block ref: ref, result: result
    
    rescue
      if @trace
        puts $!
        puts $!.backtrace.join("\n")
      end
      send_block ref: ref, error: { class: $!.class.name, text: $!.to_s }
    end
    
    # :nodoc: important that this method is called from reactor thread only
    def process_input data
      # To be free from :keys and 'keys'
      data = Hashie::Mash.new(data) unless data.is_a?(Hashie::Mash)
      if data.serial != @in_serial
        error "framing error (wrong serial:)"
      else
        @in_serial += 1
        if (cmd = data.cmd) != nil
          execute_command(cmd, data.serial, data.args || [], data.kwargs || {})
        else
          ref = data.ref
          if ref
            if (block = @callbacks.delete(ref)) != nil
              block.call(Hashie::Mash.new(result: data.result, error: data.error))
            end
          else
            error "framing error: no ref in block #{data.inspect}"
          end
        end
      end
    end
  end
  
  # Interface to the remote provider via Farcall protocols. Works the same as if the object
  # is local and yields block in return, unlike Farcall::Interface that blocks
  #
  # RemoteInterface transparently creates methods as you call them to speedup subsequent
  # calls.
  #
  class Interface
    
    # Create interface connected to some endpoint ar transpost.
    #
    # Please remember that Farcall::Transport instance could be used with only
    # one connected object, unlike Farcall::Endpoint, which could be connected to several
    # consumers.
    #
    # @param [Farcall::Endpoint|Farcall::Transport] arg either endpoint or a transport
    #        to connect interface to
    def initialize(endpoint)
      @endpoint = endpoint
    end
    
    def method_missing(method_name, *arguments, **kw_arguments, &block)
      instance_eval <<-End
        def #{method_name} *arguments, **kw_arguments, &block
          @endpoint.call '#{method_name}', *arguments, **kw_arguments, &block
        end
      End
      @endpoint.call method_name, *arguments, **kw_arguments, &block
    end
    
    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end
  
  class Provider < Farcall::Provider
    
    attr_accessor :endpoint
    
    def far_interface
      endpoint.remote
    end
  
  end
end

