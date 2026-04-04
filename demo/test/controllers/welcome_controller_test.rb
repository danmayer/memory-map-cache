require "test_helper"

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  test "should load the index dashboard natively" do
    get root_url
    assert_response :success
    assert_select "h1", "MemoryMapCache & LayeredStore"
  end

  test "should successfully boot dynamic benchmark metrics organically without gem load crashes" do
    # Because Rails.env is exactly 'test', the controller implicitly mounts ENVs [PROCESSES=1, ITERATIONS=1, PAYLOADS=100]
    # dropping the execution sequence of `bench_cache_multiprocess.rb` cleanly from ~30s down to <0.3s without blocking the test suite.
    get benchmark_url
    assert_response :success
    
    # Assert visually tracking the Kernel OS bindings natively injected
    assert_match /OS Kernel Architecture:/, response.body
    
    # Assert visually tracking the generated markdown markdown parsed structurally via Redcarpet!
    assert_match /Performance Benchmark Results/, response.body
  end
end
