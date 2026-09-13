# frozen_string_literal: true

require "console"
require "io/endpoint/ssl_endpoint"
require "io/stream"
require "protocol/smtp/client"

require_relative "endpoint"

module Async
  module SMTP
    # Connects to an endpoint and hands you the conversation.
    #
    #   Async do
    #     Async::SMTP::Client.open(Async::SMTP::Endpoint.parse("smtp://localhost:1025")) do |client|
    #       client.deliver(from: "me@example.com", to: "you@example.com", body: message)
    #     end
    #   end
    #
    # One connection per client, because SMTP transactions are stateful: two
    # senders sharing a socket would interleave their envelopes. The session
    # is set up once — greeting, EHLO, STARTTLS, EHLO again — and every
    # message after that is one transaction on it.
    class Client
      # Connect, yield the client, and close it afterwards.
      #
      # @parameter endpoint [IO::Endpoint::Generic] Where to connect.
      # @parameter options [Hash] Passed to {initialize}.
      # @yields {|client| ...}
      #   @parameter client [Client]
      def self.open(endpoint, **options)
        new(endpoint, **options).then do |client|
          begin
            yield(client)
          ensure
            client.close
          end
        end
      end

      # @parameter endpoint [IO::Endpoint::Generic] Where to connect.
      # @parameter domain [String] The domain to introduce ourselves as.
      # @parameter starttls [Boolean] Upgrade the connection when the server
      #   offers it (RFC 3207). On by default: a submission server that
      #   advertises it expects to be taken up on it.
      # @parameter ssl_context [OpenSSL::SSL::SSLContext | Nil] The context for
      #   that upgrade; the endpoint's own TLS options are used otherwise.
      # @parameter options [Hash] Passed to Protocol::SMTP::Client.
      def initialize(endpoint, domain: "localhost", starttls: true, ssl_context: nil, **options)
        @endpoint = endpoint
        @domain = domain
        @starttls = starttls
        @ssl_context = ssl_context
        @options = options

        @peer = nil
        @connection = nil
      end

      # @attribute [IO::Endpoint::Generic] Where this client connects.
      attr_reader :endpoint

      # @attribute [String] The domain this client introduces itself as.
      attr_reader :domain

      # The session, connected and introduced. Idempotent: every call after the
      # first returns the same conversation.
      #
      # @returns [Protocol::SMTP::Client]
      def connection
        @connection ||= start
      end

      # Whether the conversation is encrypted, which is only knowable once
      # there is a conversation — so this connects if nothing else has yet.
      #
      # @returns [Boolean]
      def secure?
        connection

        @secure == true
      end

      # What the server's EHLO advertised.
      # @returns [Hash(String, String)]
      def extensions = connection.extensions

      # @parameter username [String]
      # @parameter password [String]
      # @returns [Protocol::SMTP::Reply]
      # @raises [Protocol::SMTP::AuthenticationError] If nothing offered is implemented.
      def authenticate(username, password)
        connection.authenticate(username, password)
      end

      # Send one message. The session is reused, so several calls are several
      # transactions on one connection, which is what an SMTP server expects.
      #
      # @parameter from [String] The envelope sender.
      # @parameter to [String | Array(String)] The envelope recipients.
      # @parameter body [String] The message, headers and all.
      # @returns [Protocol::SMTP::Reply] The reply to the message itself.
      # @raises [Protocol::SMTP::ReplyError] If the transaction was refused.
      def deliver(from:, to:, body:)
        connection.transaction(from: from, to: to, body: body)
      end

      # Say QUIT, if there is anyone to say it to, and close the socket.
      # protocol-smtp never closes a stream it did not open, so that half is
      # here too.
      def close
        quit
        disconnect
      end

      private

        def quit
          @connection&.quit
        rescue ::Protocol::SMTP::Error, IOError, SystemCallError => error
          # The server hung up before its 221; there is nothing left to say,
          # but the socket is still ours to close.
          Console.debug(self) {"Connection ended before QUIT: #{error.message}"}
        end

        def disconnect
          @connection&.close
        rescue IOError, SystemCallError => error
          Console.debug(self) {"Connection closed abruptly: #{error.message}"}
        ensure
          @connection = nil
          @peer = nil
        end

        def start
          @peer = @endpoint.connect
          @secure = @endpoint.is_a?(::IO::Endpoint::SSLEndpoint)

          ::Protocol::SMTP::Client.new(wrap(@peer), **@options).tap do |client|
            client.hello(@domain)
            upgrade(client)
          end
        end

        # RFC 3207: the upgrade happens over the bare socket, and everything
        # the server said before it is void — so EHLO again and keep the
        # extension list from the encrypted half of the conversation.
        def upgrade(client)
          case @starttls && !@secure && client.starttls?
          when true
            client.starttls.then do |reply|
              case reply.positive?
              when true
                client.stream = wrap(secure(@peer))
                @secure = true
                client.hello(@domain)
              end
            end
          end
        end

        # Reuse the endpoint's own TLS configuration — ssl_context, ssl_params,
        # hostname and all — rather than inventing a second way to spell it.
        def secure(peer)
          ::IO::Endpoint::SSLEndpoint.new(@endpoint, ssl_context: @ssl_context).then do |endpoint|
            endpoint.make_socket(peer).tap do |socket|
              # Without SNI a shared-hosting server sends the wrong
              # certificate, and OpenSSL has nothing to verify the name against.
              case endpoint.hostname
              when nil then nil
              else socket.hostname = endpoint.hostname
              end

              socket.connect
            end
          end
        end

        def wrap(peer) = ::IO::Stream::Buffered.wrap(peer)
    end
  end
end
