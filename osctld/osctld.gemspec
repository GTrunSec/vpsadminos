lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'osctld/version'

Gem::Specification.new do |s|
  s.name        = 'osctld'

  if ENV['VPSADMIN_BUILD_ID']
    s.version   = "#{OsCtld::VERSION}.build#{ENV['VPSADMIN_BUILD_ID']}"
  else
    s.version   = OsCtld::VERSION
  end

  s.summary     =
  s.description = 'Management daemon for vpsAdmin OS'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.license     = 'GPL'

  s.required_ruby_version = '>= 2.0.0'

  s.add_runtime_dependency 'concurrent-ruby', '~> 1.0.5'
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'ipaddress', '~> 0.8.3'
  s.add_runtime_dependency 'libosctl', s.version
  s.add_runtime_dependency 'ruby-lxc', '~> 1.2.2'
  s.add_runtime_dependency 'rake'
  s.add_runtime_dependency 'yard'
end
