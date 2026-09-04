# frozen_string_literal: true

require "date"
require "bigdecimal"
require "bigdecimal/util"
require "yaml"

require_relative "facturx/version"
require_relative "facturx/invoice_data"
require_relative "facturx/config"
require_relative "facturx/xml_generator"
require_relative "facturx/pdf_embedder"
require_relative "facturx/pdf_extractor"
require_relative "facturx/validator"

module FacturX
  class Error < StandardError; end
  class ValidationError < Error; end

  # High-level helper: build a Factur-X PDF from config or data.
  #
  # @param input_pdf [String] path to the source PDF
  # @param output_pdf [String] path for the output Factur-X PDF
  # @param data [InvoiceData, Hash] invoice data (or a hash to build InvoiceData from)
  # @param config_path [String, nil] optional YAML config file
  # @return [String] path to the generated PDF
  def self.generate(input_pdf:, output_pdf:, data: nil, config_path: nil)
    invoice_data = if data.is_a?(InvoiceData)
                     data
                   elsif config_path
                     Config.new(config_path).to_invoice_data
                   elsif data.is_a?(Hash)
                     InvoiceData.new(data)
                   else
                     raise ArgumentError, "Provide :data, :config_path, or a Hash"
                   end

    xml = XmlGenerator.new(invoice_data).generate
    result = PdfEmbedder.new(xml).embed(input_pdf, output_pdf)
    Validator.validate_pdf(result)
    result
  end
end
