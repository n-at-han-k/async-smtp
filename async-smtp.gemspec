# frozen_string_literal: true

require_relative "lib/async/smtp/version"

Gem::Specification.new do |spec|
  spec.name = "async-smtp"
  spec.version = Async::SMTP::VERSION
  spec.authors = ["Nathan K"]
  spec.email = ["nathankidd@hey.com"]

  spec.summary = "An asynchronous SMTP server."

  spec.description = <<~DESC
    Binds protocol-smtp's state machine to an endpoint and runs it on the
    async reactor, one task per connection — what async-http is to
    protocol-http.
  DESC

  spec.homepage = "https://github.com/n-at-han-k/async-smtp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob(["lib/**/*.rb", "*.md", "LICENSE"], base: __dir__)
  spec.require_paths = ["lib"]

  spec.add_dependency "async", ">= 2.0"
  spec.add_dependency "io-endpoint", "~> 0.18"
  spec.add_dependency "io-stream", "~> 0.14"
  spec.add_dependency "protocol-smtp", "~> 0.1"

  spec.add_development_dependency "lefthook", "~> 2.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.60"
  spec.add_development_dependency "sus", "~> 0.37"
end
