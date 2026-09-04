# frozen_string_literal: true

require "spec_helper"

RSpec.describe FacturX::InvoiceData do
  let(:valid_attrs) do
    {
      profile: "EN16931",
      number: "202609-1",
      issue_date: Date.new(2026, 9, 1),
      currency_code: "EUR",
      seller: { name: "Forever Bije", country_code: "FR" },
       buyer:  { name: "Pierlis", country_code: "FR", electronic_address: "423137629", electronic_address_scheme: "0225" },
       legal_notes: { "PMT" => "Recovery fee: 40 EUR", "PMD" => "Late payment interest applies", "AAB" => "No early payment discount" },
      line_items: [
        { id: "1", name: "Service", quantity: 1, unit_code: "C62", price_amount: 100.00, line_total_amount: 100.00, tax_percent: 20.0, tax_category: "S" }
      ],
      tax_breakdowns: [
        { taxable_amount: 100.00, tax_amount: 20.00, tax_percent: 20.0, tax_category: "S" }
      ],
      line_extension_amount: 100.00,
      tax_exclusive_amount: 100.00,
      tax_inclusive_amount: 120.00,
      payable_amount: 120.00
    }
  end

  describe "#initialize" do
    it "creates an invoice with default values" do
      inv = FacturX::InvoiceData.new
      expect(inv.profile).to eq("EN16931")
      expect(inv.currency_code).to eq("EUR")
      expect(inv.line_items).to eq([])
    end

    it "accepts custom attributes" do
      inv = FacturX::InvoiceData.new(valid_attrs)
      expect(inv.number).to eq("202609-1")
      expect(inv.issue_date).to eq(Date.new(2026, 9, 1))
    end
  end

  describe "#profile_id" do
    it "returns correct ID for EN16931" do
      expect(FacturX::InvoiceData.new(profile: "EN16931").profile_id).to eq("urn:cen.eu:en16931:2017")
    end

    it "returns correct ID for MINIMUM" do
      expect(FacturX::InvoiceData.new(profile: "MINIMUM").profile_id).to eq("urn:factur-x.eu:1p0:minimum")
    end

    it "defaults to EN16931 for unknown profiles" do
      expect(FacturX::InvoiceData.new(profile: "UNKNOWN").profile_id).to eq("urn:cen.eu:en16931:2017")
    end
  end

  describe "#validate" do
    it "returns no errors for valid data" do
      inv = FacturX::InvoiceData.new(valid_attrs)
      expect(inv.validate).to be_empty
    end

    it "flags missing number" do
      inv = FacturX::InvoiceData.new(valid_attrs.merge(number: nil))
      expect(inv.validate).to include(/number is required/i)
    end

    it "flags missing seller name" do
      inv = FacturX::InvoiceData.new(valid_attrs.merge(seller: { name: "" }))
      expect(inv.validate).to include(/seller name is required/i)
    end

    it "requires the buyer electronic address for EN16931" do
      attrs = valid_attrs.merge(buyer: valid_attrs[:buyer].reject { |key, _| key == :electronic_address })
      expect(FacturX::InvoiceData.new(attrs).validate).to include(/Buyer electronic address \(BT-49\)/)
    end

    it "flags empty line items" do
      inv = FacturX::InvoiceData.new(valid_attrs.merge(line_items: []))
      expect(inv.validate).to include(/at least one line item/i)
    end

    it "flags inconsistent totals" do
      inv = FacturX::InvoiceData.new(valid_attrs.merge(line_extension_amount: 999.00))
      expect(inv.validate).to include(/Line total/i)
    end

    it "flags a line total that does not match quantity and price" do
      attrs = valid_attrs.merge(line_items: [valid_attrs[:line_items].first.merge(line_total_amount: 99.00)])
      expect(FacturX::InvoiceData.new(attrs).validate).to include(/quantity.*price/i)
    end

    it "flags payable totals that ignore prepaid amounts" do
      attrs = valid_attrs.merge(prepaid_amount: 20.00)
      expect(FacturX::InvoiceData.new(attrs).validate).to include(/Payable amount/i)
    end

    it "rejects unknown profiles" do
      expect(FacturX::InvoiceData.new(valid_attrs.merge(profile: "UNKNOWN")).validate).to include(/Unknown profile/)
    end
  end

  describe "#valid?" do
    it "is true for valid data" do
      expect(FacturX::InvoiceData.new(valid_attrs)).to be_valid
    end

    it "is false for invalid data" do
      expect(FacturX::InvoiceData.new).not_to be_valid
    end
  end
end
