# frozen_string_literal: true

require_relative "lib/facturx/version"

Gem::Specification.new do |spec|
  spec.name          = "facturx"
  spec.version       = FacturX::VERSION
  spec.authors       = ["Forever Bije"]
  spec.email         = ["team@foreverbije.com"]

  spec.summary       = "Generate Factur-X / ZUGFeRD conformant hybrid PDF invoices"
  spec.description   = "Lightweight Ruby library and CLI for generating Factur-X (EN 16931) " \
                       "conformant PDF/A-3b invoices with embedded CII XML. " \
                       "Auto-extracts data from existing PDFs or accepts structured input."
  spec.homepage      = "https://github.com/foreverbije/facturx"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files         = Dir["lib/**/*", "bin/*", "README.md", "LICENSE"]
  spec.bindir        = "bin"
  spec.executables   = ["facturx"]
  spec.require_paths = ["lib"]

  spec.add_dependency "zugpferd", "~> 0.3"
  spec.add_dependency "hexapdf",  "~> 1.10"
  spec.add_dependency "nokogiri", "~> 1.16"
  spec.add_dependency "pdf-reader", "~> 2.14"

  spec.add_development_dependency "rspec",   "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.75"
end
