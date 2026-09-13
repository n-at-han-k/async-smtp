# frozen_string_literal: true

require "async/smtp"

describe Async::SMTP do
  it "has a version number" do
    expect(Async::SMTP::VERSION).not.to be_nil
  end
end
