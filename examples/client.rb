#!/usr/bin/env ruby
# frozen_string_literal: true

# Send two messages over one connection. Run examples/server.rb first.

require_relative "../lib/async/smtp"

Async do
  endpoint = Async::SMTP::Endpoint.parse("smtp://127.0.0.1:2525")

  Async::SMTP::Client.open(endpoint, domain: "client.example.test") do |client|
    $stderr.puts "extensions: #{client.extensions.inspect}, secure: #{client.secure?}"

    2.times do |index|
      reply = client.deliver(
        from: "me@example.test",
        to: "you@example.test",
        body: "Subject: Message #{index}\r\n\r\nSent by async-smtp.\r\n",
      )

      $stderr.puts reply
    end
  end
end
