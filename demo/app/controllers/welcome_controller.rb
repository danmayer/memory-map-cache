class WelcomeController < ApplicationController
  def index
    # Pure statically cacheable landing page
  end

  def simulate
    @mode = params[:mode] || "layered"
    
    case @mode
    when "redis"
      @cache = ::DEMO_REDIS
    when "memory_map"
      @cache = ::DEMO_MMAP
    else
      @cache = ::DEMO_LAYERED
    end

    @hits = 0
    @misses = 0

    subscriber = ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      if event.payload[:hit]
        @hits += 1
      else
        @misses += 1
      end
    end

    @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    @data = 250.times.map do |i|
      @cache.fetch("heavy_fragment_#{i}", expires_in: 3.minutes) do
        sleep 0.005 
        "User Interface Fragment Index #{i} generated at #{Time.now.to_f}"
      end
    end
    
    @end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @elapsed_ms = ((@end_time - @start_time) * 1000).round(2)
    
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
  
  def clear
    ::DEMO_REDIS.clear
    ::DEMO_MMAP.clear
    redirect_to simulate_path(mode: params[:mode]), notice: "Testing sandbox databases completely wiped!"
  end
end
