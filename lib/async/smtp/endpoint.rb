# frozen_string_literal: true

require "io/endpoint/host_endpoint"
require "io/endpoint/ssl_endpoint"
require "uri"

module Async
  module SMTP
    # Where a server listens, or a client connects to. Thin sugar over
    # IO::Endpoint: SMTP has no scheme negotiation to do, just a host and a
    # port, with 25 the default that matters, 587 the one people actually
    # configure, and 465 the one that is encrypted before a byte is sent.
    module Endpoint
      # The port an MTA listens on for mail from other MTAs.
      DEFAULT_PORT = 25

      # The submission port (RFC 6409), which is what a client normally wants.
      SUBMISSION_PORT = 587

      # Implicit TLS (RFC 8314): encrypted from the first byte, no STARTTLS.
      SECURE_PORT = 465

      # The schemes #parse understands, and the port each implies.
      PORTS = {
        "smtp"       => DEFAULT_PORT,
        "submission" => SUBMISSION_PORT,
        "smtps"      => SECURE_PORT,
      }.freeze

      # The schemes that are encrypted before the conversation starts.
      SECURE_SCHEMES = ["smtps"].freeze

      module_function

      # @parameter host [String] The host to connect to, or bind to.
      # @parameter port [Integer] The port.
      # @parameter secure [Boolean] Wrap the connection in TLS immediately,
      #   rather than leaving it to STARTTLS.
      # @parameter options [Hash] Passed to IO::Endpoint, which is where
      #   ssl_context, ssl_params, hostname, timeout and the rest live.
      # @returns [IO::Endpoint::Generic]
      def for(host, port = DEFAULT_PORT, secure: false, **options)
        case secure
        when true then ::IO::Endpoint.ssl(host, port, hostname: host, **options)
        else ::IO::Endpoint.tcp(host, port, **options)
        end
      end

      # "smtps://mail.example.com" -> an endpoint for it, on port 465, with
      # TLS. An unknown scheme is treated as plain SMTP on port 25, because a
      # host name on its own is the common case.
      #
      # @parameter url [String] The URL to parse.
      # @returns [IO::Endpoint::Generic]
      def parse(url, **options)
        URI.parse(url).then do |uri|
          self.for(
            uri.host,
            uri.port || PORTS.fetch(uri.scheme, DEFAULT_PORT),
            secure: SECURE_SCHEMES.include?(uri.scheme),
            **options,
          )
        end
      end
    end
  end
end

__END__

describe "async/smtp/endpoint" do
  it "defaults to the port an MTA listens on, and takes any other" do
    Async::SMTP::Endpoint.for("mail.example.com").to_s.should.include "25"
    Async::SMTP::Endpoint.for("mail.example.com", 2525).to_s.should.include "2525"
  end

  it "wraps the connection in TLS when asked" do
    endpoint = Async::SMTP::Endpoint.for("mail.example.com", Async::SMTP::Endpoint::SECURE_PORT, secure: true)

    endpoint.should.be.kind_of IO::Endpoint::SSLEndpoint
    endpoint.hostname.should == "mail.example.com"
  end

  it "maps each scheme it knows to its port" do
    Async::SMTP::Endpoint.parse("smtp://mail.example.com").to_s.should.include "25"
    Async::SMTP::Endpoint.parse("submission://mail.example.com").to_s.should.include "587"
    Async::SMTP::Endpoint.parse("smtps://mail.example.com").to_s.should.include "465"

    # An explicit port wins:
    Async::SMTP::Endpoint.parse("smtp://mail.example.com:2525").to_s.should.include "2525"
  end

  it "only makes smtps secure, because only smtps is encrypted from the first byte" do
    Async::SMTP::Endpoint.parse("smtps://mail.example.com").should.be.kind_of IO::Endpoint::SSLEndpoint
    Async::SMTP::Endpoint.parse("smtp://mail.example.com").should.not.be.kind_of IO::Endpoint::SSLEndpoint
    Async::SMTP::Endpoint.parse("submission://mail.example.com").should.not.be.kind_of IO::Endpoint::SSLEndpoint
  end
end
