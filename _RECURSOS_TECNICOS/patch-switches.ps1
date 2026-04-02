begin
  File.open('extract_switches.rb', 'w') do |f|
    f.puts '# encoding: utf-8'
    f.puts 'module Graphics'
    f.puts '  class << self'
    f.puts '    unless method_defined?(:old_update_for_switches)'
    f.puts '      alias old_update_for_switches update'
    f.puts '    end'
    f.puts '    def update'
    f.puts '      old_update_for_switches'
    f.puts '      if !@switches_extracted && defined?() && defined?()'
    f.puts '        @switches_extracted = true'
    f.puts '        File.open(\"switches_names.txt\", \"w\") do |sf|'
    f.puts '          .switches.each_with_index do |name, i|'
    f.puts '            next if name.nil? || name.empty?'
    f.puts '            if name.downcase.include?(\"nuzlocke\") || name.downcase.include?(\"heroico\") || name.downcase.include?(\"muert\") || name.downcase.include?(\"fallecid\") || name.downcase.include?(\"muerte\")'
    f.puts '              sf.puts \"#{i}: #{name}\"'
    f.puts '            end'
    f.puts '          end'
    f.puts '        end'
    f.puts '      end'
    f.puts '    end'
    f.puts '  end'
    f.puts 'end'
  end
rescue => e
end
