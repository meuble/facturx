# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "facturx"
require "tempfile"
require "yaml"

RSpec.configure do |config|
  config.color = true
  config.formatter = :documentation
end
