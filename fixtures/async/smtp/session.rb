# frozen_string_literal: true

require "async/smtp"

module Async
  module SMTP
    # Bind an ephemeral port, serve it for the duration of the block, and give
    # the block a client connected to it. The tests that matter here are the
    # ones that go over a real socket, because the socket is this gem's half.
    module Session
      module_function

      def serve(handler, server_options: {}, client_options: {}, &block)
        Sync do |task|
          bound = ::IO::Endpoint.tcp("127.0.0.1", 0).bound

          begin
            endpoint = bound.local_address_endpoint
            server = Server.for(endpoint, domain: "mail.example.test", **server_options, &handler)
            server_task = task.async do
              bound.accept {|peer, address| server.accept(peer, address)}
            end

            Client.open(endpoint, domain: "client.example.test", **client_options, &block)
          ensure
            server_task&.stop
            bound.close
          end
        end
      end
    end
  end
end
