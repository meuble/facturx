# frozen_string_literal: true

require "date"
require "bigdecimal"
require "bigdecimal/util"

module FacturX
  # Structured data model for a Factur-X / EN 16931 invoice.
  # All monetary amounts are stored as BigDecimal to avoid floating-point drift.
  class InvoiceData
    attr_accessor :profile, :number, :issue_date, :due_date, :currency_code,
                  :note, :buyer_reference, :payment_terms,
                  :seller, :buyer, :line_items, :tax_breakdowns,
                  :line_extension_amount, :tax_exclusive_amount,
                  :tax_inclusive_amount, :payable_amount, :prepaid_amount

    # Factur-X profile identifiers
    PROFILES = {
      "MINIMUM"   => "urn:factur-x.eu:1p0:minimum",
      "BASICWL"   => "urn:factur-x.eu:1p0:basicwl",
      "BASIC"     => "urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic",
      "EN16931"   => "urn:cen.eu:en16931:2017",
      "EXTENDED"  => "urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:extended"
    }.freeze

    def initialize(attrs = {})
      @profile                = attrs[:profile] || "EN16931"
      @number                 = attrs[:number]
      @issue_date             = attrs[:issue_date]
      @due_date               = attrs[:due_date]
      @currency_code          = attrs[:currency_code] || "EUR"
      @note                   = attrs[:note]
      @buyer_reference        = attrs[:buyer_reference]
      @payment_terms          = attrs[:payment_terms]
      @seller                 = attrs[:seller] || {}
      @buyer                  = attrs[:buyer] || {}
      @line_items             = attrs[:line_items] || []
      @tax_breakdowns         = attrs[:tax_breakdowns] || []
      @line_extension_amount  = to_bd(attrs[:line_extension_amount])
      @tax_exclusive_amount   = to_bd(attrs[:tax_exclusive_amount])
      @tax_inclusive_amount   = to_bd(attrs[:tax_inclusive_amount])
      @payable_amount         = to_bd(attrs[:payable_amount])
      @prepaid_amount         = to_bd(attrs[:prepaid_amount] || 0)
    end

    def profile_id
      PROFILES[profile.to_s.upcase] || PROFILES["EN16931"]
    end

    def customization_id
      case profile.to_s.upcase
      when "MINIMUM"  then "urn:factur-x.eu:1p0:minimum"
      when "BASICWL"  then "urn:factur-x.eu:1p0:basicwl"
      when "BASIC"    then "urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic"
      when "EXTENDED" then "urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:extended"
      else "urn:cen.eu:en16931:2017"
      end
    end

    # Validate required fields for EN 16931.
    # Returns an array of error messages (empty if valid).
    def validate
      errors = []
      errors << "Invoice number is required" if blank?(@number)
      errors << "Issue date is required"     unless @issue_date.is_a?(Date)
      errors << "Seller name is required"    if blank?(@seller[:name])
      errors << "Buyer name is required"     if blank?(@buyer[:name])
      errors << "At least one line item is required" if @line_items.empty?
      errors << "Currency code is required"  if blank?(@currency_code)

      # Monetary totals consistency
      calc_line_total = @line_items.sum { |li| to_bd(li[:line_total_amount]) }
      calc_tax_total  = @tax_breakdowns.sum { |tb| to_bd(tb[:tax_amount]) }
      calc_grand      = calc_line_total + calc_tax_total

      if @line_extension_amount && (@line_extension_amount - calc_line_total).abs > 0.01
        errors << "Line total (#{@line_extension_amount}) does not match sum of line items (#{calc_line_total})"
      end

      if @tax_inclusive_amount && (@tax_inclusive_amount - calc_grand).abs > 0.01
        errors << "Grand total (#{@tax_inclusive_amount}) does not match computed total (#{calc_grand})"
      end

      errors
    end

    def valid?
      validate.empty?
    end

    private

    def to_bd(value)
      return nil if value.nil?
      value.is_a?(BigDecimal) ? value : value.to_d
    rescue
      nil
    end

    def blank?(str)
      str.nil? || str.to_s.strip.empty?
    end
  end
end
