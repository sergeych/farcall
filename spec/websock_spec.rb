require 'spec_helper'
require 'eventmachine'

def standard_check_wsclient(cnt1, r1, r2, r3)
  r1 = Hashie::Mash.new(r1)
  r2 = Hashie::Mash.new(r2)

  r1.kwargs.hello.should == 'world'
  r1.superpong.should == [1, 2, 3]
  r2.kwargs.hello.should == 'world'
  r2.superpong.should == [1, 2, 10]

  cnt1.should == 2
end

def standard_check(cnt1, r1, r2, r3)
  r1.error.should == nil
  r1.result.kwargs.hello.should == 'world'
  r1.result.superpong.should == [1, 2, 3]
  r2.error.should == nil
  r2.result.kwargs.hello.should == 'world'
  r2.result.superpong.should == [1, 2, 10]
  r3.error[:class].should == 'RuntimeError'
  r3.error.text.should == 'test error'
  cnt1.should == 3
end


def setup_endpoints
  c1, c2, c3, c4 = 4.times.map { EM::Channel.new }

  @e1 = EmFarcall::Endpoint.new c1, c2
  @e2 = EmFarcall::Endpoint.new c3, c4

  c2.subscribe { |x| c3 << x }
  c4.subscribe { |x| c1 << x }

  @e2.on :superping do |*args, **kwargs|
    if kwargs[:need_error]
      raise 'test error'
    end
    { superpong: args, kwargs: kwargs }
  end
  [@e1, @e2]
end

describe 'em_farcall' do

  it 'exchange messages' do
    r1   = nil
    r2   = nil
    r3   = nil
    cnt1 = 0

    EM.run {
      e1, e2 = setup_endpoints
      e1.call 'superping', 1, 2, 3, hello: 'world' do |r|
        r1   = r
        cnt1 += 1
      end

      e1.call 'superping', 1, 2, 10, hello: 'world' do |r|
        r2   = r
        cnt1 += 1
      end

      e1.call 'superping', 1, 2, 10, need_error: true, hello: 'world' do |r|
        r3   = r
        cnt1 += 1
        EM.stop
      end

      EM.add_timer(4) {
        EM.stop
      }
    }
    standard_check(cnt1, r1, r2, r3)
  end

  it 'uses remote interface' do
    r1   = nil
    r2   = nil
    r3   = nil
    cnt1 = 0

    EM.run {
      e1, e2 = setup_endpoints
      i      = EmFarcall::Interface.new e1

      i.superping(1, 2, 3, hello: 'world') { |r|
        r1   = r
        cnt1 += 1
      }

      i.superping 1, 2, 10, hello: 'world' do |r|
        r2   = r
        cnt1 += 1
      end

      i.superping 1, 2, 10, need_error: true, hello: 'world' do |r|
        r3   = r
        cnt1 += 1
        EM.stop
      end

      i.test_not_existing

      EM.add_timer(4) {
        EM.stop
      }
    }
    standard_check(cnt1, r1, r2, r3)
  end

  it 'runs via websockets' do
    r1   = nil
    r2   = nil
    r3   = nil
    cnt1 = 0

    EM.run {
      params = {
          :host => 'localhost',
          :port => 8088
      }
      e1     = nil
      e2     = nil

      EM::WebSocket.run(params) do |ws|
        ws.onopen { |handshake|
          e2 = EmFarcall::WsServerEndpoint.new ws

          e2.on :superping do |*args, **kwargs|
            if kwargs[:need_error]
              raise 'test error'
            end
            { superpong: args, kwargs: kwargs }
          end
        }
      end


      EM.defer {
        t1 = Farcall::WebsocketJsonClientTransport.new 'ws://localhost:8088/test'
        i  = Farcall::Interface.new transport: t1

        r1   = i.superping(1, 2, 3, hello: 'world')
        cnt1 += 1

        r2   = i.superping 1, 2, 10, hello: 'world'
        cnt1 += 1

        expect {
          r3 = i.superping 1, 2, 10, need_error: true, hello: 'world'
        }.to raise_error(Farcall::RemoteError, "RuntimeError: test error")

        expect {
          r3 = i.superping_bad 13, 2, 10, hello: 'world'
        }.to raise_error(Farcall::RemoteError, /NoMethodError/)


        EM.stop
      }
      EM.add_timer(4) {
        EM.stop
      }
    }

    standard_check_wsclient(cnt1, r1, r2, r3)
  end


  class WsProvider < EmFarcall::Provider
    def superping *args, **kwargs
      if kwargs[:need_error]
        raise 'test error'
      end
      { superpong: args, kwargs: kwargs }
    end
  end

  it 'runs via websockets with provider' do
    r1   = nil
    r2   = nil
    r3   = nil
    cnt1 = 0

    EM.run {
      params = {
          :host => 'localhost',
          :port => 8088
      }
      e1     = nil
      e2     = nil

      EM::WebSocket.run(params) do |ws|
        ws.onopen { |handshake|
          e2 = EmFarcall::WsServerEndpoint.new ws, provider: WsProvider.new
        }
      end


      EM.defer {
        t1 = Farcall::WebsocketJsonClientTransport.new 'ws://localhost:8088/test'
        i  = Farcall::Interface.new transport: t1

        r1   = i.superping(1, 2, 3, hello: 'world')
        cnt1 += 1

        r2   = i.superping 1, 2, 10, hello: 'world'
        cnt1 += 1

        expect {
          r3 = i.superping 1, 2, 11, need_error: true, hello: 'world'
        }.to raise_error(Farcall::RemoteError, "RuntimeError: test error")

        expect {
          r3 = i.superping_bad 13, 2, 10, need_error: true, hello: 'world'
        }.to raise_error(Farcall::RemoteError, /NoMethodError/)


        EM.stop
      }
      EM.add_timer(4) {
        EM.stop
      }
    }

    standard_check_wsclient(cnt1, r1, r2, r3)
  end

  it 'calls from server to client' do
    data1 = nil
    data2 = nil
    done  = nil

    order         = 0
    block_order   = 0
    promise_order = 0

    EM.run {
      params = {
          :host => 'localhost',
          :port => 8088
      }
      EM::WebSocket.run(params) do |ws|
        ws.onopen { |handshake|
          server = EmFarcall::WsServerEndpoint.new ws

          # EM channels are synchronous so if we call too early call will be simply lost. This,
          # though, should not happen to the socket - so why?
          server.call(:test_method, 'hello', foo: :bar) { block_order = order+=1 }.success { |result|
            data2         = result
            promise_order = order += 1
          }.fail { |e|
            puts "Error #{e}"
          }.always { |item|
            done = item
            EM.stop
          }
        }
      end

      EM.defer {
        t1 = Farcall::WebsocketJsonClientTransport.new 'ws://localhost:8088/test'
        Farcall::Endpoint.open(t1) { |client|
          client.on(:test_method) { |args, kwargs|
            data1 = { 'nice' => [args, kwargs] }
            { done: :success }
          }
        }
      }

      EM.add_timer(1) {
        EM.stop
      }
    }
    data1.should == { 'nice' => [['hello'], { 'foo' => 'bar' }] }
    data2.should == { 'done' => 'success' }
    done.should be_instance_of(Farcall::Promise)
    block_order.should == 1
    promise_order.should == 2
    done.data.should == data2
  end


end
