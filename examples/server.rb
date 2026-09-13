#!/usr/bin/env ruby
# frozen_string_literal: true

# An SMTP server on the async reactor, one task per connection.
#
# Test with: ruby examples/client.rb, or
#            swaks --to you@example.test --server localhost:2525

require_relative "../lib/async/smtp"

Async do
  endpoint = Async::SMTP::Endpoint.for("127.0.0.1", 2525)

  Async::SMTP::Server.for(endpoint, domain: "mail.example.test") do |message|
    $stderr.puts "#{message.from} -> #{message.to.join(", ")} (#{message.bytesize} bytes): #{message.subject}"

    Protocol::SMTP::Reply.ok("Queued")
  end.run
end
