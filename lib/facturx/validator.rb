# frozen_string_literal: true

require "hexapdf"
require "nokogiri"

module FacturX
  # Validates the parts of a Factur-X artifact that can be checked locally.
  # Full EN 16931 Schematron validation requires the official rule files and
  # can be enabled by passing a CII XSD path.
  class Validator
    def self.validate_pdf(path, schema_path: ENV["FACTURX_CII_SCHEMA"])
      new(schema_path: schema_path).validate_pdf(path)
    end

    def initialize(schema_path: nil)
      @schema_path = schema_path
    end

    def validate_pdf(path)
      raise ValidationError, "Output PDF not found: #{path}" unless File.exist?(path)

      document = HexaPDF::Document.open(path)
      filespec = embedded_files(document).find { |entry| entry[:F].to_s == PdfEmbedder::FACTURX_FILENAME }
      raise ValidationError, "Factur-X XML attachment is missing" unless filespec
      raise ValidationError, "Factur-X attachment must have AFRelationship=Alternative" unless filespec[:AF] == :Alternative

      embedded_file = filespec[:EF]&.[](:F)
      raise ValidationError, "Factur-X embedded file stream is missing" unless embedded_file
      raise ValidationError, "Factur-X attachment must use application/xml" unless embedded_file[:Subtype] == :"application#2Fxml"
      raise ValidationError, "PDF/A output intent is missing an ICC profile" unless document.catalog[:OutputIntents]&.to_a&.any? { |intent| intent[:DestOutputProfile] }

      xml = Nokogiri::XML(embedded_file.stream) { |config| config.strict }
      validate_schema(xml)
      path
    rescue Nokogiri::XML::SyntaxError => e
      raise ValidationError, "Embedded Factur-X XML is invalid: #{e.message}"
    end

    private

    def embedded_files(document)
      names = document.catalog.names[:EmbeddedFiles]
      return [] unless names

      names[:Names].to_a.each_slice(2).map(&:last)
    end

    def validate_schema(xml)
      return unless @schema_path
      raise ValidationError, "CII schema not found: #{@schema_path}" unless File.exist?(@schema_path)

      errors = Nokogiri::XML::Schema(File.read(@schema_path)).validate(xml)
      return if errors.empty?

      raise ValidationError, "CII schema validation failed: #{errors.map(&:message).join('; ')}"
    end
  end
end
