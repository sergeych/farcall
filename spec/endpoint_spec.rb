require 'spec_helper'

# The sample class that exports all its methods to the remote callers:
#
class TestProvider < Farcall::Provider

  attr :foo_calls, :a, :b

  def foo a, b, optional: 'none'
    @foo_calls = (@foo_calls || 0) + 1
    @a, @b     = a, b
    return "Foo: #{a+b}, #{optional}"
  end
end


describe 'endpoint' do
  include Farcall

  it 'should do RPC call with provider/interface' do
    tc = Farcall::LocalConnection.new

    ea = Farcall::Endpoint.new tc.a
    eb = Farcall::Endpoint.new tc.b

    TestProvider.new endpoint: ea
    eb.provider = "Hello world"

    i  = Farcall::Interface.new endpoint: eb
    i2 = Farcall::Interface.new endpoint: eb
    ib = Farcall::Interface.new endpoint: ea

    expect(-> { i.foo() }).to raise_error Farcall::RemoteError

    i.foo(10, 20).should == 'Foo: 30, none'
    i2.foo(5, 6, optional: 'yes!').should == 'Foo: 11, yes!'

    i.a.should == 5
    i.b.should == 6

    ib.split.should == ['Hello', 'world']
  end

  def check_protocol format
    s1, s2 = Socket.pair(:UNIX, :STREAM, 0)

    tp = TestProvider.new socket: s1, format: format
    i  = Farcall::Interface.new socket: s2, format: format, provider: "Hello world"

    expect(-> { i.foo() }).to raise_error Farcall::RemoteError

    i.foo(10, 20).should == 'Foo: 30, none'
    i.foo(5, 6, optional: 'yes!').should == 'Foo: 11, yes!'

    i.a.should == 5
    i.b.should == 6

    tp.far_interface.split.should == ['Hello', 'world']
  end

  it 'should connect json via shortcut' do
    check_protocol :json
  end

  it 'should connect boss via shortcut' do
    check_protocol :boss
  end

end
