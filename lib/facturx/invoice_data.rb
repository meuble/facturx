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
                   :legal_notes,
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
      @legal_notes            = attrs[:legal_notes] || {}
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
      PROFILES.fetch(profile.to_s.upcase) { PROFILES["EN16931"] }
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
      profile_name = profile.to_s.upcase
      errors << "Unknown profile: #{profile}" unless PROFILES.key?(profile_name)
      errors << "Invoice number is required" if blank?(@number)
      errors << "Issue date is required"     unless @issue_date.is_a?(Date)
      errors << "Due date cannot be before issue date" if @issue_date.is_a?(Date) && @due_date.is_a?(Date) && @due_date < @issue_date
      errors << "Seller name is required"    if blank?(@seller[:name])
      errors << "Buyer name is required"     if blank?(@buyer[:name])
      if profile_name != "MINIMUM" && blank?(@buyer[:electronic_address])
        errors << "Buyer electronic address (BT-49) is required for #{profile_name}"
      end
      unless profile_name == "MINIMUM"
        %w[PMT PMD AAB].each do |code|
          errors << "French legal note #{code} is required (BR-FR-05/BT-22)" if blank?(@legal_notes[code] || @legal_notes[code.to_sym])
        end
      end
      errors << "At least one line item is required" if @line_items.empty?
      errors << "Currency code is required"  if blank?(@currency_code)
      errors << "Currency code must be a 3-letter code" unless @currency_code.to_s.match?(/\A[A-Z]{3}\z/)

      @line_items.each_with_index do |line_item, index|
        quantity = amount_or_zero(line_item[:quantity] || line_item[:invoiced_quantity])
        price = amount_or_zero(line_item[:price_amount] || line_item[:net_price])
        line_total = amount_or_zero(line_item[:line_total_amount] || line_item[:line_extension_amount])
        errors << "Line item #{index + 1} quantity must be positive" if quantity <= 0
        errors << "Line item #{index + 1} price must not be negative" if price < 0
        if (quantity * price - line_total).abs > 0.01
          errors << "Line item #{index + 1} total does not match quantity × price"
        end
      end

      # Monetary totals consistency
      calc_line_total = @line_items.sum { |li| amount_or_zero(li[:line_total_amount] || li[:line_extension_amount]) }
      calc_tax_total  = @tax_breakdowns.sum { |tb| amount_or_zero(tb[:tax_amount]) }
      calc_grand      = calc_line_total + calc_tax_total

      if @line_extension_amount && (@line_extension_amount - calc_line_total).abs > 0.01
        errors << "Line total (#{@line_extension_amount}) does not match sum of line items (#{calc_line_total})"
      end

      if @tax_inclusive_amount && (@tax_inclusive_amount - calc_grand).abs > 0.01
        errors << "Grand total (#{@tax_inclusive_amount}) does not match computed total (#{calc_grand})"
      end

      if @tax_exclusive_amount && (@tax_exclusive_amount - calc_line_total).abs > 0.01
        errors << "Tax-exclusive total does not match line total"
      end

      if @payable_amount && @tax_inclusive_amount && (@payable_amount - (@tax_inclusive_amount - @prepaid_amount)).abs > 0.01
        errors << "Payable amount does not match grand total minus prepaid amount"
      end

      taxable_total = @tax_breakdowns.sum { |tb| amount_or_zero(tb[:taxable_amount] || tb[:basis_amount]) }
      if @tax_breakdowns.any? && (taxable_total - calc_line_total).abs > 0.01
        errors << "Taxable amounts do not match the line total"
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
    rescue StandardError
      nil
    end

    def amount_or_zero(value)
      to_bd(value) || BigDecimal("0")
    end

    def blank?(str)
      str.nil? || str.to_s.strip.empty?
    end
  end
end
