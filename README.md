# Farcall

## Description

The simple and elegant cross-platform RPC protocol that uses any formatter/transport capable of
transmitting dictionary-like objects, for example, JSON, 
[BOSS](https://github.com/sergeych/boss_protocol), XML, BSON and many others. This gem
supports out of the box JSON and [BOSS](https://github.com/sergeych/boss_protocol) protocols. 

RPC is made asynchronously, each call can have any return values. While one call is waiting,
other calls can be executed. The protocol is bidirectional Call parameters could be
both arrays of arguments and keyword arguments, return value could be any object, e.g. array, 
dictionary, wahtever.

Exception/errors transmitting is also supported. The interface is very simple and rubyish. The 
protocol is very easy to implement if there is no implementation, see 
[Farcall protocol specification](https://github.com/sergeych/farcall/wiki). Java library for
Android and desktop is coming soon.

## Installation

Add this line to your application's Gemfile:

```ruby
    gem 'farcall'
    # If you want to use binary-effective boss encoding:
    # gem 'noss-protocol', '>= 1.4.1' 
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install farcall

## Usage

```ruby

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
    
    # create instance and export it to some connected socket:
    TestProvider.new socket: connected_socket # default format is JSON
    
    # or using boss, if you need to pass dates and binary data
    TestProvider.new socket: connected_socket, format: :boss
```

Suppose whe have some socket connected to one above, then TestProvider methods are available via
this connection:

```ruby

    i = Farcall::Interface.new socket: client_socket
    # or
    # i = Farcall::Interface.new socket: client_socket, format: :boss

    # Plain arguments
    i.foo(10, 20).should == 'Foo: 30, none'
    
    # Plain and keyword arguments
    i.foo(5, 6, optional: 'yes!').should == 'Foo: 11, yes!'

    # the exceptions on the remote side are conveyed:
    expect(-> { i.foo() }).to raise_error Farcall::RemoteError

    # new we can read results from the remote side state:
    i.a.should == 5
    i.b.should == 6
```

More creation options ofr both provider and interface creation are:

* `endpoint:` at this point please refrain of using it as endpoint interface is going to change a 
              bit
* `transport:` subclass the `Farcall::Transport` and provide your own. It overrides `socket:`, 
               `input:` and `ouput:` parameters.
* `input:` and `output:` should be presented both or none - override `socket` - provide streams to
                         build the transport over.
                         
## guessing JSON or BOSS

Each one has its pros and contras. 

JSON is widely accepted, and there is a JSON support in literally any platform. It is to some extent
human readable (well, without line breaks - almost not ;). Still, it has no support for data 
date/time types so you should convert them somehow, its support for UTF8 is a myth (almost everywhere 
almost all UTF8 characters are escaped so the text gets many times bigger when transfering). The
binary data has to be converted to some text form too, like base64. All this compensate its goods. 
The same, except for UTF8, is right for XML.

[BOSS](https://github.com/sergeych/boss_protocol) is not widely used, and known to me implementations
exist only for Ruby, Java, Python and I've heard of ObjectiveC implementation. But it is very space-
effective, can effectively transfer binary data, date/time objects and unlimited length integer out
of the box. If caches string so when passing large object trees with same keys it provides very
effective data. It is even more comact that Python's pickle, Ruby's marshalled objects and Java 
serialized data. Ideal to fast command transfering when reaction time matters, or network speed is
low.

So, I would recommend:

- of you transfer small data portions limited to JSON data types, use JSON

- if you transfer UTF8 texts with national characters, use BOSS
 
- if you transfer audio, video, images, large arrays and hashes - use BOSS
 
- if you need BOSS but can't find it on your platform, use both and contact me :)

## Documentation

* [Farcall protocol](https://github.com/sergeych/farcall/wiki)


* Gem [online docs](http://www.rubydoc.info/gems/farcall)

## Contributing

1. Fork it ( https://github.com/[my-github-username]/farcall/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Do not forget ot add specs and ensure all of them pass
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create a new Pull Request
