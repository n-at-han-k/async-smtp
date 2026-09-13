# frozen_string_literal: true

require "async/smtp"
require "async/smtp/session"

describe Async::SMTP::Server do
  let(:messages) {[]}
  let(:handler) {proc {|message| messages << message; Protocol::SMTP::Reply.ok("queued")}}

  def serve(**options, &block)
    Async::SMTP::Session.serve(handler, **options, &block)
  end

  it "drives the conversation and hands each message to the handler" do
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
  end

  with "a handler that refuses the message" do
    let(:handler) {proc {Protocol::SMTP::Reply.rejected("No thanks")}}

    it "sends that refusal" do
      serve do |client|
        expect do
          client.deliver(from: "me@example.test", to: "you@example.test", body: "Hi\r\n")
        end.to raise_exception(Protocol::SMTP::ReplyError) do |error|
          expect(error.reply.code).to be == 550
        end
      end
    end
  end

  with "a handler that answers with a string" do
    let(:handler) {proc {"queued as 42"}}

    it "makes it the text of a 250" do
      serve do |client|
        reply = client.deliver(from: "me@example.test", to: "you@example.test", body: "Hi\r\n")

        expect(reply.code).to be == 250
        expect(reply.text).to be == "queued as 42"
      end
    end
  end

  with "a handler that answers with nothing" do
    let(:handler) {proc {nil}}

    it "says so with a 4xx, because the client may try again" do
      serve do |client|
        expect do
          client.deliver(from: "me@example.test", to: "you@example.test", body: "Hi\r\n")
        end.to raise_exception(Protocol::SMTP::ReplyError) do |error|
          expect(error.reply.code).to be == 451
        end
      end
    end
  end

  with "a handler that raises" do
    let(:handler) {proc {raise "boom"}}

    it "keeps the connection and answers 451, rather than dropping the client" do
      serve do |client|
        expect do
          client.deliver(from: "me@example.test", to: "you@example.test", body: "Hi\r\n")
        end.to raise_exception(Protocol::SMTP::ReplyError) do |error|
          expect(error.reply.code).to be == 451
        end

        # The conversation survived the failure:
        expect(client.connection.noop.code).to be == 250
      end
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
