require "test_helper"

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  test "should load the index dashboard natively" do
    get root_url
    assert_response :success
    assert_select "h1", "MemoryMapCache & LayeredStore"
  end

  test "should load the benchmark UI instantly without blocking" do
    get benchmark_url
    assert_response :success
    assert_match /OS Kernel Architecture:/, response.body
    assert_match /Live Streaming Telemetry/, response.body
  end

  test "should explicitly trigger the benchmark background hook and stream output natively" do
    # Trigger benchmark execution logic!
    post benchmark_start_url
    assert_response :success

    # Because Rails.env is exactly 'test', the controller implicitly mounts ENVs [PROCESSES=1, ITERATIONS=1, PAYLOADS=100]
    # dropping the execution sequence of `bench_cache_multiprocess.rb` cleanly down to <0.3s.
    
    # Wait for the native thread execution to cleanly output content...
    # Since executing `bundle exec ruby` inherently forces a cold boot taking ~1.0s,
    # we mimic the Javascript client tracking sequence organically:
    10.times do
      get benchmark_results_url
      break if response.body.include?("Benchmark Array Execution Completed Successfully")
      sleep 0.5
    end

    get benchmark_results_url
    assert_response :success
    
    # Assert visually tracking the generated markdown markdown parsed structurally via Redcarpet!
    assert_match /Performance Benchmark Results/, response.body
    assert_match /Benchmark Array Execution Completed Successfully/, response.body
  end
end
