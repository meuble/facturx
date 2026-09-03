# frozen_string_literal: true

require "zugpferd"
require "date"
require "nokogiri"

module FacturX
  # Generates a CII D16B XML string from InvoiceData using zugpferd.
  class XmlGenerator
    def initialize(invoice_data)
      @data = invoice_data
    end

    # Returns the XML string.
    def generate
      validate!
      invoice = build_zugpferd_invoice
      xml = Zugpferd::CII::Writer.new.write(invoice)
      apply_french_fixes!(xml)
    end

    private

    def validate!
      errors = @data.validate
      raise "Invoice validation failed:\n  - #{errors.join("\n  - ")}" unless errors.empty?
    end

    def apply_french_fixes!(xml)
      doc = Nokogiri::XML(xml)

      # BR-FR-10: Add schemeID="0002" to Seller ID (SIREN)
      # Must apply to both SellerTradeParty/ID and SpecifiedLegalOrganization/ID
      seller = doc.at("//ram:SellerTradeParty")
      if seller
        seller.xpath(".//ram:ID[not(@schemeID)]").each do |id_node|
          if id_node.text.strip.match?(/^\d{9}$/)
            id_node["schemeID"] = "0002"
          end
        end
      end

      # BR-FR-08: Set BusinessProcess based on payment status (B1 for unpaid B2B, B2 for paid)
      bp = doc.at("//ram:BusinessProcessSpecifiedDocumentContextParameter/ram:ID")
      if bp
        paid = (@data.prepaid_amount || 0).to_d
        total = (@data.tax_inclusive_amount || 0).to_d
        due = (@data.payable_amount || 0).to_d
        if paid == total && due == 0
          bp.content = "B2"
        else
          bp.content = "B1"
        end
      end

      # BR-FR-05: Add French legal notes (PMT, PMD, AAB) - add BEFORE closing tag
      exchanged_doc = doc.at("//rsm:ExchangedDocument")
      if exchanged_doc
        %w[PMT PMD AAB].each do |code|
          note = doc.create_element("ram:IncludedNote")
          content = doc.create_element("ram:Content")
          content.content = "Non applicable"
          subject = doc.create_element("ram:SubjectCode")
          subject.content = code
          note.add_child(content)
          note.add_child(subject)
          exchanged_doc.add_child(note)
        end
      end

      doc.to_xml(indent: 2)
    end

    def build_zugpferd_invoice
      invoice = Zugpferd::Model::Invoice.new(
        number:        @data.number,
        issue_date:    @data.issue_date,
        currency_code: @data.currency_code,
        profile_id:    @data.profile_id,
        customization_id: @data.customization_id
      )

      invoice.note            = @data.note            if @data.note
      invoice.buyer_reference = @data.buyer_reference if @data.buyer_reference
      invoice.due_date        = @data.due_date        if @data.due_date
      invoice.delivery_date   = @data.due_date        if @data.due_date

      invoice.seller = build_trade_party(@data.seller)
      invoice.buyer  = build_trade_party(@data.buyer)

      invoice.line_items = @data.line_items.map { |li| build_line_item(li) }
      invoice.tax_breakdown = build_tax_breakdown if @data.tax_breakdowns.any?
      invoice.monetary_totals = build_monetary_totals

      if @data.seller[:iban]
        invoice.payment_instructions = Zugpferd::Model::PaymentInstructions.new(
          payment_means_code: @data.seller[:payment_means_code] || "58",
          account_id:         normalize_iban(@data.seller[:iban])
        )
      end

      invoice
    end

    def build_trade_party(hash)
      party = Zugpferd::Model::TradeParty.new(
        name: hash[:name]
      )

      addr_fields = {
        postal_zone:  hash[:postal_zone],
        street_name:  hash[:street_name],
        city_name:    hash[:city_name],
        country_code: hash[:country_code] || "FR"
      }
      addr_fields.compact!
      addr_fields.transform_values! { |v| v.to_s.strip }
      addr_fields.reject! { |_, v| v.empty? }

      # Always create postal address if any address field is present
      # zugpferd handles nil city_name by omitting the element (not self-closing)
      if addr_fields.any?
        party.postal_address = Zugpferd::Model::PostalAddress.new(
          postal_zone:  addr_fields[:postal_zone],
          street_name:  addr_fields[:street_name],
          city_name:    addr_fields[:city_name],
          country_code: addr_fields[:country_code] || "FR"
        )
      end

      party.vat_identifier        = hash[:vat_identifier]        if hash[:vat_identifier]
      party.legal_registration_id = hash[:legal_registration_id].to_s.strip unless hash[:legal_registration_id].to_s.strip.empty?

      # For buyer: if legal_registration_id is a 14-digit SIRET,
      # set identifier (ram:ID / BT-46) to the 9-digit SIREN to avoid
      # B2C misclassification by the PPF.
      reg_id = hash[:legal_registration_id].to_s.strip
      unless reg_id.empty?
        if reg_id.match?(/^\d{14}$/)
          # SIRET → use first 9 digits (SIREN) for identifier
          party.identifier = reg_id[0, 9]
        else
          party.identifier = reg_id
        end
      end

      party.trading_name          = hash[:trading_name].to_s.strip          unless hash[:trading_name].to_s.strip.empty?

      if hash[:electronic_address]
        party.electronic_address        = hash[:electronic_address]
        party.electronic_address_scheme = hash[:electronic_address_scheme] || "EM"
      end

      # BR-FR-12: BT-49 (buyer electronic address) is mandatory in France.
      # Ensure buyer always has a URIUniversalCommunication element.
      # If no email was provided, fall back to a placeholder so zugpferd emits it.
      unless party.electronic_address
        party.electronic_address        = "contact@client.fr"
        party.electronic_address_scheme = "EM"
      end

      party
    end

    def build_line_item(hash)
      item = Zugpferd::Model::LineItem.new(
        id:                    hash[:id].to_s,
        invoiced_quantity:     hash[:quantity] || hash[:invoiced_quantity] || 1,
        unit_code:             hash[:unit_code] || "C62",
        line_extension_amount: hash[:line_total_amount] || hash[:line_extension_amount] || 0
      )

      item.note = hash[:note] if hash[:note]

      item.item = Zugpferd::Model::Item.new(
        name:         hash[:name] || hash[:description] || "Item",
        description:  hash[:description],
        tax_percent:  hash[:tax_percent] || hash[:tax_rate] || 0,
        tax_category: hash[:tax_category] || "S"
      )

      price_amount = hash[:price_amount] || hash[:net_price] || 0
      item.price = Zugpferd::Model::Price.new(
        amount:        price_amount,
        base_quantity: hash[:base_quantity] || 1
      )

      item
    end

    def build_tax_breakdown
      subtotals = @data.tax_breakdowns.map do |tb|
        Zugpferd::Model::TaxSubtotal.new(
          taxable_amount: tb[:taxable_amount] || tb[:basis_amount] || 0,
          tax_amount:     tb[:tax_amount]     || 0,
          percent:        tb[:tax_percent]    || tb[:percent]      || 0,
          category_code:  tb[:tax_category]   || tb[:category_code] || "S",
          currency_code:  @data.currency_code
        )
      end

      total_tax = subtotals.sum { |s| s.tax_amount }

      Zugpferd::Model::TaxBreakdown.new(
        tax_amount:   total_tax,
        currency_code: @data.currency_code,
        subtotals:    subtotals
      )
    end

    def build_monetary_totals
      Zugpferd::Model::MonetaryTotals.new(
        line_extension_amount: @data.line_extension_amount || 0,
        tax_exclusive_amount:  @data.tax_exclusive_amount  || 0,
        tax_inclusive_amount:  @data.tax_inclusive_amount  || 0,
        payable_amount:        @data.payable_amount        || 0,
        prepaid_amount:        @data.prepaid_amount        || 0
      )
    end

    def normalize_iban(iban)
      iban.to_s.gsub(/\s/, "")
    end
  end
end
