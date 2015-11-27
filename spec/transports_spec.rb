require 'spec_helper'
require 'stringio'

describe 'transports' do
  include Farcall

  it 'should provide debug transport' do
    s1, s2 = Socket.pair(:UNIX, :STREAM, 0)
    t1 = Farcall::DebugSocketStream.new s1, 0.01
    t2 = Farcall::SocketStream.new s2

    data = 'Not too long string'
    data2 = 'the end'
    t = Time.now
    Thread.start {
      t1.write data
      t1.write data2
    }
    x = t2.read data.length
    x.should == data
    x = data2.length.times.map { t2.read }.join('')
    x.should == data2
  end

  it 'should run json transport' do
    s1, s2 = Socket.pair(:UNIX, :STREAM, 0)

    j1 = Farcall::JsonTransport.new socket: s1
    j2 = Farcall::JsonTransport.new socket: s2

    j2.receive_data { |data|
      j2.send_data({ echo: data })
    }

    results = []
    j1.receive_data { |data|
      results << data
    }

    j1.send_data({ foo: "bar" })
    j1.send_data({ one: 2 })
    sleep 0.01
    j1.close
    j2.close

    results.should == [{ 'echo' => { 'foo' => 'bar' } }, { 'echo' => { 'one' => 2 } }]
  end

  it 'should run json transport with long delimiter' do
    s1, s2 = Socket.pair(:UNIX, :STREAM, 0)

    j1 = Farcall::JsonTransport.new socket: s1, delimiter: "\n\n\n\n"
    j2 = Farcall::JsonTransport.new socket: s2, delimiter: "\n\n\n\n"

    j2.receive_data { |data|
      j2.send_data({ echo: data })
    }

    results = []
    j1.receive_data { |data|
      results << data
    }

    j1.send_data({ foo: "bar" })
    j1.send_data({ one: 2 })
    sleep 0.01
    j1.close
    j2.close

    results.should == [{ 'echo' => { 'foo' => 'bar' } }, { 'echo' => { 'one' => 2 } }]
  end


end
