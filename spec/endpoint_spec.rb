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

  def self.doncallpublic

  end

  def get_hash
    { 'foo' => 'bar', 'bardd' => 'buzz', 'last' => 'item', 'bar' => 'test'}
  end

  private

  def dontcall

  end
end

class StringProvider < Farcall::Provider
  def initialize(str)
    @str = str
  end

  def provide_hash
    { 'bar' => 'test', 'foo' => 'bar'}
  end

  def value
    @str
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

    # ib.split.should == ['Hello', 'world']

    expect(-> { i.dontcall() }).to raise_error Farcall::RemoteError, /NoMethodError/
    expect(-> { i.sleep() }).to raise_error Farcall::RemoteError, /NoMethodError/
    expect(-> { i.abort() }).to raise_error Farcall::RemoteError, /NoMethodError/
    expect(-> { i.doncallpublic() }).to raise_error Farcall::RemoteError, /NoMethodError/
    expect(-> { i.initialize(1) }).to raise_error Farcall::RemoteError, /NoMethodError/
  end

  def check_protocol format
    s1, s2 = Socket.pair(:UNIX, :STREAM, 0)

    tp = TestProvider.new socket: s1, format: format
    i  = Farcall::Interface.new socket: s2, format: format, provider: StringProvider.new("bar")

    expect(-> { i.foo() }).to raise_error Farcall::RemoteError

    i.foo(10, 20).should == 'Foo: 30, none'
    i.foo(5, 6, optional: 'yes!').should == 'Foo: 11, yes!'

    i.a.should == 5
    i.b.should == 6

    i.get_hash.foo.should == 'bar'
    i.get_hash.bar.should == 'test'
    tp.far_interface.value.should == 'bar'
    tp.far_interface.provide_hash.bar.should == 'test'
    tp.far_interface.provide_hash.foo.should == 'bar'
  end

  it 'should connect json via shortcut' do
    check_protocol :json
  end

  it 'boss connect boss via shortcut' do
    check_protocol :boss
  end

end
