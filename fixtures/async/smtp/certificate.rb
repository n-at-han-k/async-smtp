# frozen_string_literal: true

require "openssl"

module Async
  module SMTP
    # A self-signed certificate for 127.0.0.1, so a test can exercise a real
    # TLS handshake without a fixture file or a certificate authority.
    module Certificate
      module_function

      def key = @key ||= OpenSSL::PKey::RSA.new(2048)

      def certificate
        @certificate ||= OpenSSL::X509::Certificate.new.tap do |certificate|
          certificate.version = 2
          certificate.serial = 1
          certificate.subject = OpenSSL::X509::Name.parse("/CN=localhost")
          certificate.issuer = certificate.subject
          certificate.public_key = key.public_key
          certificate.not_before = Time.now - 60
          certificate.not_after = Time.now + 3600

          OpenSSL::X509::ExtensionFactory.new.tap do |factory|
            factory.subject_certificate = certificate
            factory.issuer_certificate = certificate
            certificate.add_extension(factory.create_extension("subjectAltName", "IP:127.0.0.1,DNS:localhost"))
          end

          certificate.sign(key, OpenSSL::Digest.new("SHA256"))
        end
      end

      # What the server presents.
      def server_context
        OpenSSL::SSL::SSLContext.new.tap do |context|
          context.cert = certificate
          context.key = key
        end
      end

      # What a client that trusts exactly this certificate uses.
      def client_context
        OpenSSL::SSL::SSLContext.new.tap do |context|
          context.cert_store = OpenSSL::X509::Store.new.tap {|store| store.add_cert(certificate)}
          context.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
      end
    end
  end
end
