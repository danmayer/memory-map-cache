class WelcomeController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:clear, :benchmark_start]

  def index
    # Pure statically cacheable landing page
  end

  def benchmark
    @system_info = `uname -a`.strip
    @ruby_info = RUBY_DESCRIPTION
    @benchmark_script_url = "https://github.com/danmayer/memory-map-cache/blob/main/bench/bench_cache_multiprocess.rb"
  end

  def benchmark_start
    file_path = Rails.root.join("tmp", "live_benchmark.md")
    FileUtils.mkdir_p(File.dirname(file_path))
    File.write(file_path, "> Initializing physical torture test array...\n\n")

    envs = Rails.env.test? ? { "PROCESSES" => "1", "ITERATIONS" => "1", "PAYLOADS" => "100" } : {}

    Thread.new do
      script_path = Rails.root.join("..", "bench", "bench_cache_multiprocess.rb")
      parser_path = Rails.root.join("..", "bench", "parse_markdown.rb")
      
      system(envs, "bundle exec ruby #{script_path} | ruby #{parser_path} >> #{file_path}")
      
      File.open(file_path, "a") { |f| f.puts "\n\n**Benchmark Array Execution Completed Successfully.**" }
    end
    
    head :ok
  end

  def benchmark_results
    file_path = Rails.root.join("tmp", "live_benchmark.md")
    content = File.exist?(file_path) ? File.read(file_path) : "Awaiting execution..."
    
    require "redcarpet"
    render plain: Redcarpet::Markdown.new(Redcarpet::Render::HTML, tables: true, fenced_code_blocks: true).render(content)
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
