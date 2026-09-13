# Changelog

## 0.1.0

- `Async::SMTP::Server`: accepts on an `IO::Endpoint`, one task per
  connection, and drives the `Protocol::SMTP::Server` conversation — greeting,
  each message to the handler, its reply back, and the socket closed at the
  end. A handler may answer with a `Reply` or a `String`; nothing, or a raised
  exception, becomes a `451`.
- `Async::SMTP::Client`: sets the session up once — greeting, `EHLO`,
  `STARTTLS`, `EHLO` again — and runs each `#deliver` as one transaction on
  it, with `#authenticate` for submission.
- `STARTTLS` (RFC 3207) on both sides, reusing the endpoint's own TLS
  configuration rather than a second way to spell it.
- `Async::SMTP::Endpoint`: `.for(host, port, secure:)` and
  `.parse("smtps://host")`, which knows the `smtp`, `submission` and `smtps`
  schemes and their ports.
