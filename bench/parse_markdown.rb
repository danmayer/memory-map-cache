# bench/parse_markdown.rb

output = $stdin.read
markdown = []
markdown << "## 🚀 Performance Benchmark Results\n\n"

current_store = nil

output.each_line do |line|
  line = line.strip
  if line.include?("Multiprocess Benchmarks for values of size")
    size = line.scan(/\d+/).last
    markdown << "### 📦 Payload Size: #{size} Bytes\n\n"
  elsif line.start_with?("==") && line.end_with?("==")
    op = line.gsub("==", "").strip
    next if op.empty? # Skip visual spacer blocks

    markdown << "#### #{op}\n"
    markdown << "| Cache Store | Operations/sec | Execution Time (s) |\n"
    markdown << "|-------------|----------------|--------------------|\n"
  elsif line =~ /Starting \d+ processes with .*? (?:on|of) (.*?) \.\.\./
    current_store = Regexp.last_match(1)
  elsif line =~ %r{\.\. finished in ([\d.]+) seconds \(([\d.]+) ops/sec\)}
    if current_store
      markdown << "| **#{current_store}** | #{Regexp.last_match(2)} ops/sec | #{Regexp.last_match(1)}s |\n"
      current_store = nil
    end
  elsif line =~ /^(mixed|write_multi|read_multi)\s+[\d.]+\s+[\d.]+\s+[\d.]+\s+\(\s*([\d.]+)\)/
    time = Regexp.last_match(2)
    markdown << "| **#{current_store} (#{Regexp.last_match(1)})** | *Not Calculated* | #{time}s |\n" if current_store
  elsif line.include?("Comparing Pipeline Architectures natively")
    markdown << "\n### 🚇 Distributed Pipeline Architecture (MGET/MSET)\n\n"
    markdown << "| Cache Store | Operations/sec | Execution Time (s) |\n"
    markdown << "|-------------|----------------|--------------------|\n"
  end
end

markdown_string = markdown.join
puts markdown_string

File.open(ENV['GITHUB_STEP_SUMMARY'], 'a') { |f| f.puts markdown_string } if ENV['GITHUB_STEP_SUMMARY']
