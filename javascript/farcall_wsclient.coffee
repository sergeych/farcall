root = exports ? this
# Farcall RPC protocol client over WebSocket transport.
#
# This script has no external dependencies except that if you want to use self-test, you'll
# need underscore.js. Test silently fails if can't find it.
#
# See protocol at github: https://github.com/sergeych/farcall/
#
# provided under MIT license.
#
# @author real.sergeych@gmail.com
#
class root.WsFarcall

  # Create transport connected to the given url. A shortcut of (new WsFarrcall(url))
  @open: (url) ->
    new WsFarcall(url)

  # Construct a protocol endpoint connected to the given url (must be ws:// or wss:// websocket
  # url)
  constructor: (@url) ->
    @in_serial = 0
    @out_serial = 0
    @openHandlers = []
    @closeHandlers = []
    @ws = new WebSocket(@url)
    @connected = false
    @promises = {}
    @commandHandlers = {}
    @ws.onopen = =>
      @connected = true
      cb(this) for cb in @openHandlers

    @ws.onclose = =>
      @connected = false
      cb(this) for cb in @closeHandlers

    @ws.onmessage = (message) =>
      @trace and console.log ">>> #{message.data}"
      @_receive(JSON.parse message.data)

  # add open callback. The callback takes a single argument - the WsFarcall instance
  onopen: (callback) ->
    @openHandlers.push callback

  # add close callback. The callback takes a single argument - the WsFarcall instance
  onclose: (callback) ->
    @closeHandlers.push callback

  # close the protocol and socket
  close: ->
    @ws.close()

  # Call remote function with the specified name. Arguments can be list and.or keyword arguments.
  # The Farcall arguments can be a list, a dictionary (keywords hash), or both. If the last argument
  # is the object, it will be treated as dictionary argument. Add extra {} to the end of list if
  # need.
  #
  # Returns Promise instance so you can add .success() (or .done()), fail() and always() handlers to
  # it. On success callback receives whatever data remote function has returned, on error it receives
  # the arcall standard error object, e.g. { error: { class: string, text: another_sting} } object.
  #
  # always handler receives and object { result: {}, error: {}} where only one of the two is set
  #
  call: (name, args...) ->
    [args, kwargs] = splitArgs(args)
    promise = @promises[@out_serial] = new Promise()
    @_send cmd: name, args: args, kwargs: kwargs
    promise

  # Add an local remote-callable function. The callback receives whatever arguments are send from
  # thre remote caller and its returned value will be passed to the remote. On error it should throw
  # an exception.
  on: (name, callback) ->
    @commandHandlers[name] = callback

  _receive: (data) ->
    if data.serial != @in_serial++
      console.error "farcall framing error"
      @close()
    else
      if data.ref != undefined
        promise = @promises[data.ref]
        delete @promises[data.ref]
        if data.error == undefined
          promise.setDone(data.result)
        else
          promise.setFail(data.error)
      else
        @_processCall data

  _send: (params) ->
    params.serial = @out_serial++
    params = JSON.stringify(params)
    @trace and console.log "<<< #{params}"
    @ws.send params

  _processCall: (data) ->
    handler = @commandHandlers[data.cmd]
    if handler
      try
        data.args.push data.kwargs
        @_send ref: data.serial, result: handler(data.args...)
      catch e
        @_send ref: data.serial, error: {class: 'RuntimeError', text: e.message}
    else
      @_send
        ref: data.serial, error: {class: 'NoMethodError', text: "method not found: #{data.cmd}"}

  @selfTest: (url, callback) ->
    if _?.isEqual(1, 1)
      p1 = false
      p2 = false
      p3 = false
      cb = false
      cbr = false
      done = false
      WsFarcall.open(url + '/fartest').onopen (fcall) ->
        fcall.call('ping', 1, 2, 3, {hello: 'world'})
        .done (data) ->
          p1 = checkEquals(data, {pong: [1, 2, 3, {hello: 'world'}]})
        fcall.call('ping', 2, 2, 3, {hello: 'world'})
        .done (data) ->
          p2 = checkEquals(data, {pong: [2, 2, 3, {hello: 'world'}]})
        fcall.call('ping', 3, 2, 3, {hello: 'world'})
        .done (data) ->
          p3 = checkEquals(data, {pong: [3, 2, 3, {hello: 'world'}]})

        fcall.on 'test_callback', (args...) ->
          cb = checkEquals(args, [5, 4, 3, {hello: 'world'}])
          # The callback request should have time to be processed
          setTimeout ->
                       done = true
                       ok = p1 and p2 and p3 and cb and cbr
                       text = switch
                         when !cb
                           'callback was not called or wrong data'
                         when !cbr
                           'callback request did not return'
                         else
                           if ok then '' else 'ping data wrong'
                       callback(ok, text)
                     , 80

        fcall.call('callback', 'test_callback', 5, 4, 3, hello: 'world')
        .done (data) ->
          cbr = true

      setTimeout ->
                   callback(false, 'timed out') if !done
                 , 5000
    else
      # can't pass test = we need underscore for it
      callback(false, "Can't test: need underscpre.js")

# Promise object let set any number of callbacks on the typical comletion events, namely success,
# failure and operation is somehow completed (always).
#
# The promise has 3 states: initial (operation us inder way), done and failed. When the operation
# is done or failed, attempt to add new handlers of the proper type will cause it immediate
# invocation.
#
# Promise can be set to equer success or error only once. All suitable handlers are called one time
# when the state is set.
root.WsFarcall.Promise = class Promise

  constructor: ->
    [@done_handlers, @fail_handlers, @always_handlers] = ([] for i in [1..3])
    @state = null
    @data = @error = undefined

  # Add callback on the success event. Can be called any number of times, all callbacks will be
  # invoked. If the state is already set to done, the callback fires immediately.
  #
  # callback receives whatever data passed to the #setSuccess() call.
  done: (callback) ->
    if @state
      callback(@data) if @state == 'done'
    else
      @done_handlers.push callback
    this

  # same as done()
  success: (callback) ->
    @done(callback)

  # Add callback on the failure event. Can be called any number of times, all callbacks will be
  # invoked. If the state is already set to failure, the callback fires immediately.
  #
  # callback receives whatever data passed to the #setFail() call.
  fail: (callback) ->
    if @state
      callback(@error) if @state == 'fail'
    else
      @fail_handlers.push callback
    this

  # Add callback on the both sucess and failure event. Can be called any number of times, all
  # callbacks will be invoked. If the state is already set to eqither done or failure, the callback
  # fires immediately.
  #
  # callback receives { error: {class: c. text: t}, result: any } object where only one (error or
  # result) exist.
  #
  # always callbacks are executed after all of #success() or #fail().
  always: (callback) ->
    if @state
      callback data: @data, error: @error
    else
      @always_handlers.push callback
    this

  # set promise to success state. If the state is already set to any, does noting. Calls all
  # corresponding callbacks passing them the `data` parameter.
  setSuccess: (data) ->
    if !@state
      @state = 'done'
      @data = data
      cb(data) for cb in @done_handlers
      @done = null
      @_fireAlways()
    this

  # same as #setSuccess()
  setDone: (data) ->
    @setSuccess data

  # set promise to failure state. If the state is already set to any, does noting. Calls all
  # corresponding callbacks passing them the `data` parameter.
  setFail: (error) ->
    if !@state
      @state = 'fail'
      @error = error
      cb(error) for cb in @fail_handlers
      @fail = null
      @_fireAlways()
    this

  isSuccess: ->
    @state == 'done'

  isFail: ->
    @state == 'fail'

  # same as #isFail
  isError: ->
    @state == 'fail'

  # promise is either done of fail (e.g. completed)
  isCompleted: ->
    !!@state

  _fireAlways: ->
    cb({error: @error, data: @data}) for cb in @always_handlers
    @always = null


# Split javascript arguments array to args and kwargs of the Farcall notaion
# e.g. if the last argument is the pbject, it will be treated as kwargs.
splitArgs = (args) ->
  last = args[args.length - 1]
  if typeof(last) == 'object'
    [args[0..-2], last]
  else
    [args, {}]


# For self-test only, relies on underscore.js
checkEquals = (a, b, text) ->
  if _.isEqual a, b
    true
  else
    console.error "#{text ? 'ERROR'}: not equal:"
    console.error "expected: #{JSON.stringify b}"
    console.error "got:      #{JSON.stringify a}"
    false


