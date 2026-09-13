# frozen_string_literal: true

require "async/smtp"
require "async/smtp/certificate"
require "async/smtp/session"

describe Async::SMTP::Client do
  let(:messages) {[]}
  let(:handler) {proc {|message| messages << message; Protocol::SMTP::Reply.ok("queued")}}

  def serve(**options, &block)
    Async::SMTP::Session.serve(handler, **options, &block)
  end

  it "sets the session up once and runs each delivery as a transaction on it" do
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

  it "introduces itself, so the server knows who it is talking to" do
    serve do |client|
      client.deliver(from: "me@example.test", to: "you@example.test", body: "Subject: Hello\r\n\r\nBody.\r\n")
    end

    expect(messages.first.helo).to be == "client.example.test"
    expect(messages.first.peer).to be == "127.0.0.1"
    expect(messages.first).not.to be(:secure?)
  end

  it "raises what the server refused" do
    serve(server_options: {maximum_message_size: 64}) do |client|
      expect do
        client.deliver(from: "me@example.test", to: "you@example.test", body: "#{"x" * 200}\r\n")
      end.to raise_exception(Protocol::SMTP::ReplyError) do |error|
        expect(error.reply.code).to be == 552
      end
    end

    expect(messages).to be(:empty?)
  end

  it "reads what the server advertised" do
    serve(server_options: {maximum_message_size: 64}) do |client|
      expect(client.connection.maximum_message_size).to be == 64
    end
  end

  with "STARTTLS" do
    let(:options) do
      {
        server_options: {ssl_context: Async::SMTP::Certificate.server_context},
        client_options: {ssl_context: Async::SMTP::Certificate.client_context},
      }
    end

    it "upgrades the connection and delivers over it" do
      serve(**options) do |client|
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

    it "carries on in the clear when told not to upgrade" do
      serve(server_options: options[:server_options], client_options: {starttls: false}) do |client|
        expect(client).not.to be(:secure?)
        expect(client.extensions).to be(:include?, "STARTTLS")
        expect(client.deliver(from: "me@example.test", to: "you@example.test", body: "Hi\r\n").code).to be == 250
      end

      expect(messages.first).not.to be(:secure?)
    end
  end

  it "closes the socket protocol-smtp would not close itself" do
    peer = nil

    Async::SMTP::Session.serve(handler) do |client|
      client.deliver(from: "me@example.test", to: "you@example.test", body: "Hi\r\n")
      peer = client.connection.stream
    end

    expect(peer).to be(:closed?)
  end
end
