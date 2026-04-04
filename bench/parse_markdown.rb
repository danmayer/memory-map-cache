# bench/parse_markdown.rb
$stdout.sync = true
puts "## 🚀 LIVE Performance Benchmark Results\n"

current_store = nil

$stdin.each_line do |line|
  line = line.strip
  if line.include?("Multiprocess Benchmarks for values of size")
    size = line.scan(/\d+/).last
    puts "\n### 📦 Payload Size: #{size} Bytes\n"
  elsif line.start_with?("==") && line.end_with?("==")
    op = line.gsub("==", "").strip
    next if op.empty?

    puts "\n#### #{op}"
    puts "| Cache Store | Operations/sec | Execution Time (s) |"
    puts "|-------------|----------------|--------------------|"
  elsif line =~ /Starting \d+ processes with .*? (?:on|of) (.*?) \.\.\./
    current_store = Regexp.last_match(1)
  elsif line =~ %r{\.\. finished in ([\d.]+) seconds \(([\d.]+) ops/sec\)}
    if current_store
      puts "| **#{current_store}** | #{Regexp.last_match(2)} ops/sec | #{Regexp.last_match(1)}s |"
      current_store = nil
    end
  elsif line =~ /^(mixed|write_multi|read_multi)\s+[\d.]+\s+[\d.]+\s+[\d.]+\s+\(\s*([\d.]+)\)/
    time = Regexp.last_match(2)
    puts "| **#{current_store} (#{Regexp.last_match(1)})** | *Not Calculated* | #{time}s |" if current_store
  elsif line.include?("Comparing Pipeline Architectures natively")
    puts "\n### 🚇 Distributed Pipeline Architecture (MGET/MSET)\n"
    puts "| Cache Store | Operations/sec | Execution Time (s) |"
    puts "|-------------|----------------|--------------------|"
  end
end
