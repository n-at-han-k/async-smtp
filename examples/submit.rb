#!/usr/bin/env ruby
# frozen_string_literal: true

# Submit a message to a real provider: STARTTLS on port 587, then AUTH.
#
#   SMTP_HOST=smtp.example.com SMTP_USER=me SMTP_PASSWORD=... ruby examples/submit.rb

require_relative "../lib/async/smtp"

Async do
  endpoint = Async::SMTP::Endpoint.for(ENV.fetch("SMTP_HOST"), Async::SMTP::Endpoint::SUBMISSION_PORT)

  Async::SMTP::Client.open(endpoint, domain: ENV.fetch("SMTP_DOMAIN", "localhost")) do |client|
    # #connect has already done the STARTTLS upgrade, if it was offered:
    raise "Refusing to send credentials in the clear!" unless client.secure?

    client.authenticate(ENV.fetch("SMTP_USER"), ENV.fetch("SMTP_PASSWORD"))

    puts client.deliver(
      from: ENV.fetch("SMTP_FROM", ENV.fetch("SMTP_USER")),
      to: ENV.fetch("SMTP_TO"),
      body: "Subject: Hello\r\n\r\nSent by async-smtp.\r\n",
    )
  end
end
