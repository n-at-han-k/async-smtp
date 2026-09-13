# frozen_string_literal: true

require "async"
require "console"
require "io/endpoint"
require "io/stream"
require "protocol/smtp/server"

module Async
  module SMTP
    # An SMTP server that accepts connections on an endpoint and hands each
    # complete message to an application handler — async-http's Server, for a
    # protocol that isn't HTTP. The conversation itself belongs to
    # protocol-smtp; what lives here is the socket, the task it runs in, the
    # loop that drives it, and the application at the end of that loop.
    #
    #   endpoint = Async::SMTP::Endpoint.for("127.0.0.1", 1025)
    #   Async::SMTP::Server.for(endpoint) { |message| Protocol::SMTP::Reply.ok }.run
    #
    # The handler is called with a Protocol::SMTP::Message and answers with a
    # Protocol::SMTP::Reply. One task per connection: a slow handler holds up
    # its own client and nobody else's.
    class Server
      # Create a server using a block as the handler.
      #
      # @parameter endpoint [IO::Endpoint::Generic] Where to listen.
      # @parameter options [Hash] Passed to {initialize}.
      def self.for(endpoint, **options, &block)
        new(block, endpoint, **options)
      end

      # @parameter app [Proc] Called with each complete message.
      # @parameter endpoint [IO::Endpoint::Generic] Where to listen.
      # @parameter domain [String] The domain this server announces itself as.
      # @parameter ssl_context [OpenSSL::SSL::SSLContext | Nil] Offer STARTTLS
      #   using this context (RFC 3207). An endpoint that is already encrypted
      #   needs none of this.
      # @parameter options [Hash] Passed to Protocol::SMTP::Server.
      def initialize(app, endpoint, domain: "localhost", ssl_context: nil, **options)
        @app = app
        @endpoint = endpoint
        @domain = domain
        @ssl_context = ssl_context
        @options = options
      end

      # @attribute [Proc] The handler each message goes to.
      attr_reader :app

      # @attribute [IO::Endpoint::Generic] Where this server listens.
      attr_reader :endpoint

      # @attribute [String] The domain this server announces itself as.
      attr_reader :domain

      # @returns [Hash] A JSON-compatible representation of this server.
      def as_json(...)
        {
          endpoint: @endpoint.to_s,
          domain:   @domain,
          secure:   !@ssl_context.nil?,
        }
      end

      # @returns [String] A JSON string representation of this server.
      def to_json(...) = as_json.to_json(...)

      # Accept one connection and talk to it until it quits or goes away.
      # Matches async-http's signature, which is what Endpoint#accept yields.
      #
      # @parameter peer [IO] The connected peer.
      # @parameter address [Addrinfo] Where it connected from.
      def accept(peer, address, task: Task.current)
        connection = connection(peer, address)

        Console.debug(self) {"Incoming connection from #{address.inspect}."}

        connection.write_greeting

        while message = connection.read_message
          connection.write_reply(reply_for(message))
        end
      rescue ::Protocol::SMTP::Error, IOError, SystemCallError => error
        # The peer's problem, not ours: log it and let this task end.
        Console.debug(self) {"Connection from #{address.inspect} ended: #{error.message}"}
      ensure
        connection&.close
      end

      # @returns [Async::Task] The task the server is running in.
      def run
        Async do |task|
          @endpoint.accept(&method(:accept))

          # Wait for the connections that are still being served:
          task.children&.each(&:wait)
        end
      end

      private

        # The one reply in the conversation that is the application's. A Reply
        # is written as it stands; a String is the text of a 250, because
        # "queued" is the whole of what most handlers want to say. Anything
        # else — nothing at all, or an exception — is this server's problem
        # rather than the client's, so it gets a 4xx and the client may try
        # again later.
        def reply_for(message)
          @app.call(message).then do |reply|
            case reply
            when ::Protocol::SMTP::Reply then reply
            when nil then ::Protocol::SMTP::Reply.new(451, "Handler did not answer")
            else ::Protocol::SMTP::Reply.ok(reply.to_s)
            end
          end
        rescue => error
          Console.error(self, "Handler failed!", error)

          ::Protocol::SMTP::Reply.new(451, "Internal error")
        end

        def connection(peer, address)
          ::Protocol::SMTP::Server.new(
            ::IO::Stream::Buffered.wrap(peer),
            domain:   @domain,
            peer:     peer_address(address),
            starttls: starttls(peer),
            **@options,
          )
        end

        # The upgrade happens over the bare socket the buffered stream was
        # wrapping, which is why the raw peer is captured here: the 220 has
        # already gone out in the clear, and anything the client sent before
        # the handshake is discarded along with the old stream (RFC 3207 4.2).
        def starttls(peer)
          case @ssl_context
          when nil then nil
          else
            proc do |stream|
              stream.flush

              ::OpenSSL::SSL::SSLSocket.new(peer, @ssl_context).then do |socket|
                socket.sync_close = true
                socket.accept

                ::IO::Stream::Buffered.wrap(socket)
              end
            end
          end
        end

        # Addrinfo for a TCP endpoint; a unix socket has no ip_address.
        def peer_address(address)
          case address.respond_to?(:ip_address)
          when true then address.ip_address
          else address.to_s
          end
        end
    end
  end
end
