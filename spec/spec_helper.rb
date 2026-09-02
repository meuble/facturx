require 'bundler/setup'
require 'zugpferd'
require 'nokogiri'
require 'yaml'
require 'date'
require 'fileutils'
require 'tempfile'

# Charger le code source (sans exécuter le code principal)
require_relative '../facturx_generator'
# Ne pas charger facturx_simple.rb ici car il contient du code qui s'exécute au chargement
# Il sera chargé séparément dans ses propres tests

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
