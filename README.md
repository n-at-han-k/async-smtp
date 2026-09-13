# async-smtp

An asynchronous SMTP server and client: [protocol-smtp](../protocol-smtp)'s
state machine bound to an endpoint and run on the [async][async] reactor, one
task per connection. What async-http is to protocol-http.

[async]: https://github.com/socketry/async

## Server

```ruby
require "async/smtp"

Async do
  endpoint = Async::SMTP::Endpoint.for("127.0.0.1", 1025)

  Async::SMTP::Server.for(endpoint, domain: "mail.example.com") do |message|
    $stderr.puts "#{message.from} -> #{message.to.join(', ')} (#{message.bytesize} bytes)"
    Protocol::SMTP::Reply.ok("queued")
  end.run
end
```

The handler is called with a `Protocol::SMTP::Message` and answers with a
`Protocol::SMTP::Reply`, or a `String` for the text of a `250`. Answering with
nothing, or raising, gets the client a `451` and the failure a log entry — the
connection survives either way. One task per connection: a slow handler holds
up its own client and nobody else's.

protocol-smtp owns the conversation; what lives here is the socket, the task,
the loop that drives `read_message`, the application at the end of it, and
closing the socket afterwards.

## Client

```ruby
Async do
  Async::SMTP::Client.open(Async::SMTP::Endpoint.for("127.0.0.1", 1025)) do |client|
    client.deliver(
      from: "me@example.com",
      to: "you@example.com",
      body: "Subject: Hello\r\n\r\nHi.\r\n",
    )
  end
end
```

One connection per client: SMTP transactions are stateful, so two senders
sharing a socket would interleave their envelopes. The session is set up once
— greeting, `EHLO`, `STARTTLS`, `EHLO` again — and each `#deliver` after that
is one transaction on it.

## TLS

`STARTTLS` is taken up whenever the server offers it, so submission to a real
provider is the same two calls plus credentials:

```ruby
endpoint = Async::SMTP::Endpoint.for("smtp.example.com", Async::SMTP::Endpoint::SUBMISSION_PORT)

Async::SMTP::Client.open(endpoint) do |client|
  raise "in the clear!" unless client.secure?

  client.authenticate(username, password)
  client.deliver(from: from, to: to, body: body)
end
```

Pass `starttls: false` to stay in the clear, or `ssl_context:` to verify
against something other than the system store. Implicit TLS (port 465) is a
property of the endpoint instead — `Endpoint.parse("smtps://...")` — and needs
no upgrade.

A server offers `STARTTLS` only when given a context to offer it with:

```ruby
Async::SMTP::Server.for(endpoint, ssl_context: context, &handler).run
```

Both halves discard everything said before the handshake, as RFC 3207 4.2
requires: the client re-`EHLO`s, and the server forgets any transaction in
progress.

## Endpoints

`Async::SMTP::Endpoint.for(host, port = 25)` and
`Async::SMTP::Endpoint.parse("smtps://mail.example.com")` both return an
`IO::Endpoint`, so anything that ecosystem already does — binding a socket
ahead of time, wrapping it in SSL, listing several addresses — works here
unchanged. `parse` knows the three schemes that matter: `smtp` (25),
`submission` (587) and `smtps` (465, encrypted from the first byte).

## Workers

`Server#run` returns the `Async::Task` it is running in, so the usual
`async-container` pattern applies if you want more than one process accepting
from the same socket:

```ruby
bound = Async::SMTP::Endpoint.for("0.0.0.0", 25).bound

Async::Container.best_container_class.new.run(count: 4) do
  Async { Async::SMTP::Server.for(bound, &handler).run }
end
```

## What it does not do

No server-side `AUTH`, no connection pool (a pool of stateful transactions is
not a pool), no queueing or retries. Those belong to the mail system built on
top, not to the transport.

## License

MIT.
