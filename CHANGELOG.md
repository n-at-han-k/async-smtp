# Changelog

## 0.1.0

- `Async::SMTP::Server`: accepts on an `IO::Endpoint` and runs a
  `Protocol::SMTP::Server` per connection, one task each.
- `Async::SMTP::Client`: sets the session up once — greeting, `EHLO`,
  `STARTTLS`, `EHLO` again — and runs each `#deliver` as one transaction on
  it, with `#authenticate` for submission.
- `STARTTLS` (RFC 3207) on both sides, reusing the endpoint's own TLS
  configuration rather than a second way to spell it.
- `Async::SMTP::Endpoint`: `.for(host, port, secure:)` and
  `.parse("smtps://host")`, which knows the `smtp`, `submission` and `smtps`
  schemes and their ports.
