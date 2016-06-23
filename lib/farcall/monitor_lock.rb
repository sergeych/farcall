require 'thread'

# :nodoc:
class MontorLock

  def initialize
    @condition = ConditionVariable.new
    @mutex = Mutex.new
  end

  def notify
    @mutex.synchronize {
      @condition.signal
    }
  end

  def wait
    @mutex.synchronize {
      @condition.wait(@mutex)
      yield if block_given?
    }
  end

end

# :nodoc:
class Semaphore

  def initialize state_set=false
    @monitor = MontorLock.new
    @state_set = state_set
  end

  def set?
    @state_set
  end

  def clear?
    !set?
  end

  def wait state
    while @state_set != state do
      @monitor.wait
    end
    @state_set
  end

  def wait_set
    wait true
  end

  def wait_clear
    wait false
  end

  def wait_change &block
    @monitor.wait {
      block.call(@state_set) if block
    }
    @state_set
  end

  def set new_state=true
    if @state_set != new_state
      @state_set = new_state
      @monitor.notify
    end
  end

  def clear
    set false
  end
end
