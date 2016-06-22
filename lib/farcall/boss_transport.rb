module Farcall

  # Boss transport is more spece-effective than json, supports more data types, and does not need
  # delimiters to separate packets in the stream. Creation parameters are the same as of
  # Farcall::Transport
  class BossTransport < Farcall::Transport
    include TransportBase

    # Create json transport, see Farcall::Transpor#create for parameters
    def initialize **params
      setup_streams **params
      @formatter = Boss::Formatter.new(@output)
      @formatter.set_stream_mode
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
      @formatter << hash
    end

    def close
      if !@closing
        @closing = true
        close_connection
        @thread and @thread.join
        @thread = nil
      end
    end

    private

    def load_loop
      Boss::Parser.new(@input).each { |object|
        on_data_received and on_data_received.call object
      }
    rescue Errno::EPIPE
      close
    rescue
      if !@closing
        STDERR.puts "Farcall::BossTransport read loop failed: #{$!.class.name}: #$!"
        STDERR.puts $!.backtrace.join("\n")
        connection_aborted $!
      else
        close
      end
    end
  end
end

