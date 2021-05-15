# frozen-string-literal: true

lib = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name           = 'fluent-plugin-protobuf-http'
  spec.version        = '0.3.0'
  spec.authors        = ['Azeem Sajid']
  spec.email          = ['azeem.sajid@gmail.com']

  spec.summary        = 'fluentd HTTP Input Plugin for Protocol Buffers'
  spec.description    = 'fluentd HTTP Input Plugin for Protocol Buffers with Single and Batch Messages Support'
  spec.homepage       = 'https://github.com/iamAzeem/fluent-plugin-protobuf-http'
  spec.license        = 'Apache-2.0'

  test_files, files   = `git ls-files -z`.split("\x0").partition do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.files          = files
  spec.executables    = files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files     = test_files
  spec.require_paths  = ['lib']

  spec.add_development_dependency 'bundler', '~> 2.1', '>= 2.1.0'
  spec.add_development_dependency 'rake', '~> 12.0'
  spec.add_development_dependency 'simplecov', '~> 0.12', '<= 0.12.2'
  spec.add_development_dependency 'test-unit', '~> 3.0'
  spec.add_runtime_dependency 'fluentd', ['>= 0.14.10', '< 2']
  spec.add_runtime_dependency 'google-protobuf', '~> 3.12', '>= 3.12.2'
end
