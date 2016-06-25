module Farcall
  # Promise let set multiple callbacks on different completion events: success, fail and completion.
  # Promisee guarantte that corresponing callbacks will be called and only once. Callbacks added
  # after completion are being called immediately.
  #
  # Promise state can be changed only once by calling either #set_success( or #set_fail().
  # Its subsequent invocations raise errors.
  #
  class Promise

    # returns data passed to the call to #set_success(data), or nil
    attr :data

    # returns data passed to the call to #set_success(error), or nil
    attr :error

    def initialize
      @state                   = nil
      @success, @fail, @always = [], [], []
    end

    def succsess?
      @state == :success
    end

    def fail?
      @state == :fail
    end

    # the promise is completed after one of #set_success(data) and #set_fail(error) is called.
    def completed?
      @state == :completed
    end

    # Add handler for the success event. If the promise is already #success? then the block
    # is called immediately, otherwise when and if the promise reach this state.
    #
    # block receives data parameter passed to #set_success(data)
    #
    # @return [Proomise] self
    def success &block
      if !completed?
        @success << block
      elsif succsess?
        block.call(@data)
      end
      self
    end

    # Add handler for the fail event. If the promise is already #fail? then the block
    # is called immediately, otherwise when and if the promise reach this state.
    #
    # Block receives error parameter passed to the #set_fail(data)
    #
    # @return [Proomise] self
    def fail &block
      if !completed?
        @fail << block
      elsif fail?
        block.call(@error)
      end
      self
    end

    # Add handler to the completion event that will receive promise instance as the parameter (thus
    # able to check state and ready #data or #error value).
    #
    # Note that `always` handlers are called after `success` or `fail` ones.
    #
    # @return [Proomise] self
    def always &block
      if !completed?
        @always << block
      else
        block.call(self)
      end
      self
    end

    # same as #always
    alias finished always

    # Set the promise as #completed? with #success? state and invoke proper handlers passing `data`
    # which is also available with #data property.
    #
    # If invoked when already #completed?, raises error.
    def set_success data
      raise "state is already set" if @state
      @state = :success
      @data  = data
      invoke @success, data
    end

    # Set the promise as #completed? with #fail? state and invoke proper handlers. passing `error`
    # which is also available with #error property.
    #
    # If invoked when already #completed?, raises error.
    def set_fail error
      raise "state is already set" if @state
      @state = :fail
      @error = error
      invoke @fail, error
    end

    private

    def invoke list, data
      list.each { |proc| proc.call(data) }
      @always.each { |proc| proc.call(self) }
      @always = @success = @fail = nil
    end
  end
end
