require 'json'
require 'socket'

module Farcall

  # Stream-like object to wrap very strange ruby socket IO
  class SocketStream

    def initialize socket
      @socket = socket
    end

    def read length=1
      # data = ''
      # while data.length < length
      #   data << @socket.recv(length - data.length, Socket::MSG_WAITALL)
      # end
      # data
      @socket.read length
    end

    def write data
      @socket.write data
    end

    def eof?
      @socket.eof?
    end

    def << data
      write data
    end

  end

  # The socket stream that imitates slow data reception over the slow internet connection
  # use to for testing only
  class DebugSocketStream < Farcall::SocketStream

    # @param [float] timeout between sending individual bytes in seconds
    def initialize socket, timeout
      super socket
      @timeout = timeout
    end

    def write data
      data.to_s.each_char { |x|
        super x
        sleep @timeout
      }
    end
  end

  # :nodoc:
  module TransportBase
    # connect socket or use streams if any
    def setup_streams input: nil, output: nil, socket: nil
      if socket
        @socket = socket
        @input  = @output = SocketStream.new(socket)
      else
        @input, @output = input, output
      end
      @input != nil && @output != nil or raise Farcall::Error, "can't setup streams"
    end

    # close connection (socket or streams)
    def close_connection
      if @socket
        if !@socket.closed?
          begin
            @socket.flush
            @socket.shutdown
          rescue Errno::ENOTCONN
          end
          @socket.close
        end
        @socket = nil
      else
        @input.close
        @output.close
      end
      @input = @output = nil
    end
  end

  # The transport that uses delimited texts formatted with JSON. Delimiter should be a character
  # sequence that will never appear in data, by default "\x00" is used. Also several \n\n\n can be
  # used, most JSON codecs never insert several empty strings
  class JsonTransport < Farcall::Transport
    include TransportBase

    # Create json transport, see Farcall::Transpor#create for parameters
    def initialize delimiter: "\x00", **params
      super()
      setup_streams **params
      @delimiter = delimiter
      @dlength   = -delimiter.length
    end

    def on_data_received= block
      super
      if block && !@thread
        @thread = Thread.start {
          load_loop
        }
      end
    end

    def send_data hash
      @output << JSON.unparse(hash) + @delimiter
    end

    def close
      if !@closing
        @closing  = true
        close_connection
        @thread and @thread.join
        @thread = nil
      end
    end

    private

    def load_loop
      buffer = ''
      while !@input.eof?
        buffer << @input.read(1)
        if buffer[@dlength..-1] == @delimiter
          on_data_received and on_data_received.call(JSON.parse(buffer[0...@dlength]))
          buffer = ''
        end
      end
    rescue Errno::EPIPE
      close
    rescue
      if !@closing
        STDERR.puts "Farcall::JsonTransport read loop failed: #{$!.class.name}: #$!"
        STDERR.puts $!.backtrace.join("\n")
        connection_aborted $!
      else
        close
      end
    end

  end
end

