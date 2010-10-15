require 'bundler'
Bundler::GemHelper.install_tasks

# --------------------------------------------------
# Tests
# --------------------------------------------------
namespace(:test) do

  desc "run framework compatibility tests"
  task(:all) do
    Dir['test/test_*.rb'].each do |path|
      cmd = "ruby -rubygems -I.:lib -I.:test/test_helper.rb #{path}"
      puts(cmd) if ENV['VERBOSE']
      system(cmd)
    end
  end
end

