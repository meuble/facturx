# frozen_string_literal: true

require "yaml"
require "date"

module FacturX
  # Loads invoice data from a YAML configuration file.
  class Config
    attr_reader :data, :overrides

    def initialize(path = nil)
      @data = default_data
      @overrides = {}
      load_file(path) if path && File.exist?(path)
      raise ArgumentError, "Config file not found: #{path}" if path && !File.exist?(path)
    end

    def to_invoice_data
      InvoiceData.new(
        profile:               @data["profile"],
        number:                @data["invoice"]["number"],
        issue_date:            parse_date(@data["invoice"]["issue_date"]),
        due_date:              parse_date(@data["invoice"]["due_date"]),
        currency_code:         @data["invoice"]["currency_code"],
        note:                  @data["invoice"]["note"],
        buyer_reference:       @data["invoice"]["buyer_reference"],
        payment_terms:         @data["invoice"]["payment_terms"],
        seller:                @data["seller"].transform_keys(&:to_sym),
        buyer:                 @data["buyer"].transform_keys(&:to_sym),
        line_items:            @data["line_items"].map { |li| li.transform_keys(&:to_sym) },
        tax_breakdowns:        @data["tax_breakdowns"].map { |tb| tb.transform_keys(&:to_sym) },
        line_extension_amount: @data["totals"]["line_extension_amount"],
        tax_exclusive_amount:  @data["totals"]["tax_exclusive_amount"],
        tax_inclusive_amount:  @data["totals"]["tax_inclusive_amount"],
        payable_amount:        @data["totals"]["payable_amount"],
        prepaid_amount:        @data["totals"]["prepaid_amount"]
      )
    end

    private

    def default_data
      {
        "profile" => "EN16931",
        "seller" => {
          "name" => "",
          "legal_registration_id" => "",
          "vat_identifier" => "",
          "postal_zone" => "",
          "street_name" => "",
          "city_name" => "",
          "country_code" => "FR",
          "electronic_address" => "",
          "electronic_address_scheme" => ""
        },
        "buyer" => {
          "name" => "",
          "legal_registration_id" => "",
          "vat_identifier" => "",
          "postal_zone" => "",
          "street_name" => "",
          "city_name" => "",
          "country_code" => "FR"
        },
        "invoice" => {
          "number" => "",
          "issue_date" => Date.today.strftime("%Y-%m-%d"),
          "due_date" => (Date.today + 30).strftime("%Y-%m-%d"),
          "currency_code" => "EUR",
          "note" => "",
          "buyer_reference" => "",
          "payment_terms" => ""
        },
        "line_items" => [],
        "tax_breakdowns" => [],
        "totals" => {
          "line_extension_amount" => 0,
          "tax_exclusive_amount" => 0,
          "tax_inclusive_amount" => 0,
          "payable_amount" => 0,
          "prepaid_amount" => 0
        }
      }
    end

    def load_file(path)
      content = YAML.safe_load(File.read(path), permitted_classes: [Date], aliases: false)
      unless content.nil? || content.is_a?(Hash)
        raise ArgumentError, "Config root must be a mapping"
      end
      @overrides = content || {}
      @data = deep_merge(@data, content || {})
    rescue Psych::SyntaxError => e
      raise "Invalid YAML syntax in #{path}: #{e.message}"
    rescue StandardError => e
      raise "Failed to load config #{path}: #{e.message}"
    end

    def deep_merge(base, overlay)
      base.merge(overlay) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end

    def parse_date(value)
      return nil if value.nil? || value.to_s.empty?
      return value if value.is_a?(Date)
      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
