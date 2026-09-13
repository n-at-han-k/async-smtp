# frozen_string_literal: true

require "async/smtp"
require "async/smtp/certificate"

describe Async::SMTP::Server do
  let(:messages) {[]}
  let(:handler) {proc {|message| messages << message; Protocol::SMTP::Reply.ok("queued")}}
  let(:server_options) {{}}
  let(:client_options) {{}}

  # Bind an ephemeral port, serve it for the duration of the block, and give
  # the block a client connected to it.
  def serve(&block)
    Sync do |task|
      bound = IO::Endpoint.tcp("127.0.0.1", 0).bound

      begin
        endpoint = bound.local_address_endpoint
        server = subject.for(endpoint, domain: "mail.example.test", **server_options, &handler)

        server_task = task.async do
          bound.accept {|peer, address| server.accept(peer, address)}
        end

        Async::SMTP::Client.open(endpoint, domain: "client.example.test", **client_options, &block)
      ensure
        server_task&.stop
        bound.close
      end
    end
  end

  it "delivers a message end to end" do
    serve do |client|
      reply = client.deliver(
        from: "me@example.test",
        to:   "you@example.test",
        body: "Subject: Hello\r\n\r\nBody.\r\n",
      )

      expect(reply.code).to be == 250
      expect(reply.text).to be == "queued"
    end

    expect(messages.size).to be == 1
    expect(messages.first.from).to be == "me@example.test"
    expect(messages.first.to).to be == ["you@example.test"]
    expect(messages.first.subject).to be == "Hello"
    expect(messages.first.helo).to be == "client.example.test"
    expect(messages.first.peer).to be == "127.0.0.1"
    expect(messages.first).not.to be(:secure?)
  end

  it "reuses one connection for several transactions" do
    serve do |client|
      2.times do |index|
        client.deliver(from: "me@example.test", to: "you@example.test", body: "Subject: #{index}\r\n\r\n.\r\n")
      end

      expect(client.extensions.keys).to be(:include?, "SIZE")
    end

    expect(messages.map(&:subject)).to be == ["0", "1"]
    # The dot the client stuffed came back off:
    expect(messages.first.body).to be == ".\r\n"
  end

  it "reports what the handler refused" do
    handler = proc {Protocol::SMTP::Reply.rejected("No thanks")}
    server_options.freeze

    Sync do |task|
      bound = IO::Endpoint.tcp("127.0.0.1", 0).bound

      begin
        endpoint = bound.local_address_endpoint
        server = subject.for(endpoint, &handler)
        server_task = task.async {bound.accept {|peer, address| server.accept(peer, address)}}

        Async::SMTP::Client.open(endpoint) do |client|
          expect do
            client.deliver(from: "me@example.test", to: "you@example.test", body: "Hi\r\n")
          end.to raise_exception(Protocol::SMTP::ReplyError) do |error|
            expect(error.reply.code).to be == 550
          end
        end
      ensure
        server_task&.stop
        bound.close
      end
    end
  end

  with "a message over the limit" do
    let(:server_options) {{maximum_message_size: 64}}

    it "refuses it at the terminating dot" do
      serve do |client|
        expect do
          client.deliver(from: "me@example.test", to: "you@example.test", body: "#{"x" * 200}\r\n")
        end.to raise_exception(Protocol::SMTP::ReplyError) do |error|
          expect(error.reply.code).to be == 552
        end
      end

      expect(messages).to be(:empty?)
    end

    it "advertises the limit, so a client can give up first" do
      serve do |client|
        expect(client.connection.maximum_message_size).to be == 64
      end
    end
  end

  with "STARTTLS" do
    let(:server_options) {{ssl_context: Async::SMTP::Certificate.server_context}}
    let(:client_options) {{ssl_context: Async::SMTP::Certificate.client_context}}

    it "upgrades the connection and delivers over it" do
      serve do |client|
        expect(client).to be(:secure?)

        reply = client.deliver(
          from: "me@example.test",
          to:   "you@example.test",
          body: "Subject: Secret\r\n\r\nBody.\r\n",
        )

        expect(reply.code).to be == 250

        # The extension list is the one from after the upgrade, which no
        # longer offers STARTTLS:
        expect(client.extensions).not.to be(:include?, "STARTTLS")
      end

      expect(messages.first.subject).to be == "Secret"
      expect(messages.first).to be(:secure?)
    end
  end

  with "a client that refuses to upgrade" do
    let(:server_options) {{ssl_context: Async::SMTP::Certificate.server_context}}
    let(:client_options) {{starttls: false}}

    it "carries on in the clear" do
      serve do |client|
        expect(client).not.to be(:secure?)
        expect(client.extensions).to be(:include?, "STARTTLS")
        expect(client.deliver(from: "me@example.test", to: "you@example.test", body: "Hi\r\n").code).to be == 250
      end

      expect(messages.first).not.to be(:secure?)
    end
  end

  with "#run" do
    it "accepts on the endpoint until the task is stopped" do
      Sync do
        bound = IO::Endpoint.tcp("127.0.0.1", 0).bound

        begin
          endpoint = bound.local_address_endpoint
          task = subject.for(bound, domain: "mail.example.test", &handler).run

          Async::SMTP::Client.open(endpoint) do |client|
            expect(client.deliver(from: "me@example.test", to: "you@example.test", body: "Subject: Run\r\n\r\n").code).to be == 250
          end
        ensure
          task&.stop
          bound.close
        end
      end

      expect(messages.first.subject).to be == "Run"
    end
  end

  it "describes itself as JSON" do
    endpoint = Async::SMTP::Endpoint.for("127.0.0.1", 2525)
    server = subject.for(endpoint, domain: "mail.example.test") {nil}

    expect(server.as_json).to be == {endpoint: endpoint.to_s, domain: "mail.example.test", secure: false}
  end
end
