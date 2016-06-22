require 'hashie'

module Farcall

  # The protocol endpoint. Takes some transport and implements Farcall protocol over
  # it. You can use it direcly or with Farcall::RemoteInterface and Farcall::LocalProvider helper
  # classes.
  #
  # Note that the returned data is converted to Hashie::Mash primarily for the sake of :key vs.
  # 'key' ambigity that otherwise might appear depending on the transport encoding protocol. Anyway
  # it is better than ruby hash ;)
  #
  # Endpoint class is thread-safe.
  class Endpoint

    # Set or get provider instance. When provider is set, its public methods are called by the remote
    # and any possible exception are passed back to caller party. You can use any ruby class instance
    # everything will work, operators, indexes[] and like.
    attr_accessor :provider

    # Create endpoint connected to some transport
    # @param [Farcall::Transport] transport
    def initialize(transport)
      @transport                  = transport
      @in_serial                  = @out_serial = 0
      @transport.on_data_received = -> (data) {
        begin
          _received(data)
        rescue
          abort :format_error, $!
        end
      }
      @send_lock                  = Mutex.new
      @receive_lock               = Mutex.new

      @waiting = {}
    end

    # The provided block will be called if endpoint functioning will be aborted.
    # The block should take |reason, exception| parameters - latter could be nil
    def on_abort &proc
      @abort_hadnler = proc
    end

    # Add the close handler. Specified block will be called when the endpoint is been closed
    def on_close &block
      @close_handler = block
    end

    # :nodoc:
    def abort reason, exception = nil
      puts "*** Abort: reason #{reason || exception.to_s}"
      @abort_hadnler and @abort_hadnler.call reason, exception
      if exception
        raise exception
      end
      close
    end

    # Close endpoint and connected transport
    def close
      @transport.close
      @transport = nil
      @close_handler and @close_handler.call
    end

    # Call remote party. Retruns immediately. When remote party answers, calls the specified block
    # if present. The block should take |error, result| parameters. If result's content hashes
    # or result itself are instances of th Hashie::Mash. Error could be nil or
    # {'class' =>, 'text' => } Hashie::Mash hash. result is always nil if error is presented.
    #
    # It is desirable to use Farcall::Endpoint#interface or
    # Farcall::RemoteInterface rather than this low-level method.
    #
    # @param [String] name of the remote command
    def call(name, *args, **kwargs, &block)
      @send_lock.synchronize {
        if block != nil
          @waiting[@out_serial] = {
              time: Time.new,
              proc: block
          }
          _send(cmd: name.to_s, args: args, kwargs: kwargs)
        end
      }
    end

    # Call the remote party and wait for the return.
    #
    # It is desirable to use Farcall::Endpoint#interface or
    # Farcall::RemoteInterface rather than this low-level method.
    #
    # @param [String] name of the remote command
    # @return [Object] any data that remote party retruns. If it is a hash, it is a Hashie::Mash
    #     instance.
    # @raise [Farcall::RemoteError]
    #
    def sync_call(name, *args, **kwargs)
      mutex          = Mutex.new
      resource       = ConditionVariable.new
      error          = nil
      result         = nil
      calling_thread = Thread.current

      mutex.synchronize {
        same_thread = false
        call(name, *args, **kwargs) { |e, r|
          error, result = e, r
          # Absolutly stupid wait for self situation
          # When single thread is used to send and receive
          # - often happens in test environments
          if calling_thread == Thread.current
            same_thread = true
          else
            resource.signal
          end
        }
        same_thread or resource.wait(mutex)
      }
      if error
        raise Farcall::RemoteError.new(error['class'], error['text'])
      end
      result
    end

    # Process remote commands. Not that provider have precedence at the moment.
    # Provided block will be executed on every remote command taking parameters
    # |name, args, kwargs|. Whatever block returns will be passed to a calling party.
    # The same any exception that the block might raise would be send back to caller.
    def on_remote_call &block
      @on_remote_call = block
    end

    # Get the Farcall::RemoteInterface connnected to this endpoint. Any subsequent calls with
    # return the same instance.
    def remote
      @remote ||= Farcall::Interface.new endpoint: self
    end

    private

    def _send(**kwargs)
      if @send_lock.locked?
        kwargs[:serial] = @out_serial
        @transport.send_data kwargs
        @out_serial += 1
      else
        @send_lock.synchronize { _send(**kwargs) }
      end
    end

    def _received(data)
      # p [:r, data]
      data = Hashie::Mash.new data

      cmd, serial, args, kwargs, ref, result, error =
          %w{cmd serial args kwargs ref result error}.map { |k| data[k] || data[k.to_sym] }
      !serial || serial < 0 and abort 'missing or bad serial'

      @receive_lock.synchronize {
        serial == @in_serial or abort "framing error (wrong serial)"
        @in_serial += 1
      }

      case
        when cmd

          begin
            result = if @provider
                       args ||= []
                       if kwargs && !kwargs.empty?
                         # ruby thing: keyqord args must be symbols, not strings:
                         fixed = {}
                         kwargs.each { |k, v| fixed[k.to_sym] = v }
                         args << fixed
                       end
                       @provider.send :remote_call, cmd.to_sym, args
                     elsif @on_remote_call
                       @on_remote_call.call cmd, args, kwargs
                     end
            _send ref: serial, result: result
          rescue Exception => e
            # puts e
            # puts e.backtrace.join("\n")

            _send ref: serial, error: { 'class' => e.class.name, 'text' => e.to_s }
          end

        when ref

          ref or abort 'no reference in return'
          (w = @waiting.delete ref) != nil and w[:proc].call(error, result)

        else
          abort 'unknown command'
      end
    end

  end

  # Could be used as a base class to export its methods to the remote. You are not limited
  # to subclassing, instead, you can set any class instance as a provider setting it to
  # the Farcall::Endpoint#provider. The provider has only one method^ which can not be accessed
  # remotely: #far_interface, which is used locally to object interface to call remote methods
  # for two-way connections.
  class Provider
    # Create an instance connected to the Farcall::Transport or Farcall::Endpoint - use what
    # suites you better.
    #
    # Please remember that Farcall::Transport instance could be used with only
    # one connected object, unlike Farcall::Endpoint, which could be connected to several
    # consumers.
    #
    # @param [Farcall::Endpoint] endpoint to connect to (no transport should be provided).
    #           note that if endpoint is specified, transport would be ignored eeven if used
    # @param [Farcall::Transport] transport to use (don't use endpoint then)
    def initialize endpoint: nil, transport: nil, **params
      if endpoint || transport || params.size > 0
        @endpoint          = if endpoint
                               endpoint
                             else
                               transport ||= Farcall::Transport.create **params
                               Farcall::Endpoint.new transport
                             end
        @endpoint.provider = self
      end
    end

    # Get remote interface
    # @return [Farcall::Interface] to call methods on the other end, e.g. if this provider would
    # like to call other party's methiod, it can do it cimply by:
    #
    #   far_interface.some_method('hello')
    #
    def far_interface
      @endpoint.remote
    end

    # close connection if need
    def close_connection
      @endpoint.close
    end

    protected

    # Override it to repond to remote calls. Base implementation let invoke only public method
    # only owned by this class. Be careful to not to expose more than intended!
    def remote_call name, args
      m = public_method(name)
      if m && m.owner == self.class
        m.call(*args)
      else
        raise NoMethodError, "method #{name} is not found"
      end
    rescue NameError
      raise NoMethodError, "method #{name} is not found"
    end

  end

  # Intervace to the remote provider via Farcall protocols. Works the same as if the object
  # would be in local data, but slower :) The same as calling Farcall::Endpoint#interface
  #
  # RemoteInterface transparently creates methods as you call them to speedup subsequent
  # calls.
  #
  # There is no way to check that the remote responds to some method other than call it and
  # catch the exception
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
    def initialize endpoint: nil, transport: nil, provider: nil, **params
      @endpoint = if endpoint
                    endpoint
                  else
                    Farcall::Endpoint.new(transport || Farcall::Transport.create(**params))
                  end
      provider and @endpoint.provider = provider
    end

    def method_missing(method_name, *arguments, **kw_arguments, &block)
      instance_eval <<-End
        def #{method_name} *arguments, **kw_arguments
          @endpoint.sync_call '#{method_name}', *arguments, **kw_arguments
        end
      End
      @endpoint.sync_call method_name, *arguments, **kw_arguments
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end
end
