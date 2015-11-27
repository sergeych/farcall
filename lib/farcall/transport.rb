
module Farcall

  # Generic error in Farcall library
  class Error < StandardError
  end

  # The error occured while executin remote method
  class RemoteError < Error
    attr :remote_class

    def initialize remote_class, text
      @remote_class = remote_class
      super "#{remote_class}: #{text}"
    end
  end

  # The transport interface. Farcall works via anything that can send and receive dictionary
  # objects. The transport should only implement Transport#send_data and invoke
  # Transport#on_data_received when incoming data are available
  class Transport

    # Create transport with a given format and parameters.
    #
    # format right now can be only :json
    #
    # creation parameters can be:
    #
    #   - socket: connect transport to some socket (should be connected)
    #
    #   - input and aoutput: two stream-like objects which support read(length) and write(data)
    #                        parameters
    #
    def self.create format: :json, **params
      case format
        when :json
          Farcall::JsonTransport.new **params
        else
          raise Farcall::Error, "unknown format: #{format}"
      end
    end

    attr :closed

    # Tansport must call this process on each incoming hash
    # passing it as the only parameter, e.g. self.on_data_received(hash)
    attr_accessor :on_data_received, :on_abort, :on_close

    # Utility function. Calls the provided block on data reception. Resets the
    # block with #on_data_received
    def receive_data &block
      self.on_data_received = block
    end

    # Transmit somehow a dictionary to the remote part
    def send_data hash
      raise 'not implemented'
    end

    # Flush and close transport
    def close
      @closed = true
      @on_close and @on_close.call
    end

    protected

    def connection_closed
      close
    end

    def connection_aborted exceptoin
      STDERR.puts "Farcall: connection aborted: #{$!.class.name}: #{$!}"
      @on_abort and @on_abort.call $!
      close
    end


  end

  # Test connection that provides 2 interconnected transports
  # TestConnection#a and TestConnection#b that could be used to connect Endpoints
  class LocalConnection

    # :nodoc:
    class Connection < Transport

      attr_accessor :other

      def initialize other_loop = nil
        if other_loop
          other_loop.other = self
          @other           = other_loop
        end
      end

      def send_data hash
        @other.on_data_received.call hash
      end

    end

    attr :a, :b

    def initialize
      @a = Connection.new
      @b = Connection.new @a
    end
  end


end
