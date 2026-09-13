# frozen_string_literal: true

require "async/smtp/endpoint"

describe Async::SMTP::Endpoint do
  with ".for" do
    it "defaults to the port an MTA listens on" do
      expect(subject.for("mail.example.com").to_s).to be(:include?, "25")
    end

    it "takes any other port" do
      expect(subject.for("mail.example.com", 2525).to_s).to be(:include?, "2525")
    end

    it "wraps the connection in TLS when asked" do
      endpoint = subject.for("mail.example.com", subject::SECURE_PORT, secure: true)

      expect(endpoint).to be_a(IO::Endpoint::SSLEndpoint)
      expect(endpoint.hostname).to be == "mail.example.com"
    end
  end

  with ".parse" do
    it "maps each scheme to its port" do
      expect(subject.parse("smtp://mail.example.com").to_s).to be(:include?, "25")
      expect(subject.parse("submission://mail.example.com").to_s).to be(:include?, "587")
      expect(subject.parse("smtps://mail.example.com").to_s).to be(:include?, "465")
    end

    it "prefers an explicit port" do
      expect(subject.parse("smtp://mail.example.com:2525").to_s).to be(:include?, "2525")
    end

    it "only makes smtps secure" do
      expect(subject.parse("smtps://mail.example.com")).to be_a(IO::Endpoint::SSLEndpoint)
      expect(subject.parse("smtp://mail.example.com")).not.to be_a(IO::Endpoint::SSLEndpoint)
      expect(subject.parse("submission://mail.example.com")).not.to be_a(IO::Endpoint::SSLEndpoint)
    end
  end
end
