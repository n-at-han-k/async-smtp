# frozen_string_literal: true

require_relative "smtp/version"

require_relative "smtp/client"
require_relative "smtp/endpoint"
require_relative "smtp/server"

# @namespace
module Async
  # An asynchronous SMTP server and client: protocol-smtp's state machine
  # bound to an endpoint, one task per connection. What async-http is to
  # protocol-http.
  #
  # @namespace
  module SMTP
  end
end
