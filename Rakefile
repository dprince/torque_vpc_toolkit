require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "torque-vpc-toolkit"
    gem.summary = %Q{Rake tasks to submit Torque jobs. }
    gem.description = %Q{Rake tasks to submit, and poll Torque jobs.}
    gem.email = "dan.prince@rackspace.com"
    gem.homepage = "http://github.com/dprince/torque_vpc_toolkit"
    gem.authors = ["Dan Prince"]
    gem.add_dependency "rake", ">= 0"
    gem.add_dependency "chef-vpc-toolkit", ">= 2.0"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "Torque VPC Toolkit #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
