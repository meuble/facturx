# frozen_string_literal: true

require "spec_helper"

RSpec.describe FacturX::Config do
  let(:valid_yaml) do
    <<~YAML
      profile: BASIC
      seller:
        name: Test Seller
        vat_identifier: FR123456789
        country_code: FR
      buyer:
        name: Test Buyer
        country_code: FR
      invoice:
        number: TEST-001
        issue_date: "2024-01-15"
        due_date: "2024-02-15"
      line_items:
        - id: "1"
          name: Test Item
          quantity: 1
          unit_code: C62
          price_amount: 100.00
          line_total_amount: 100.00
          tax_percent: 20.0
          tax_category: S
      tax_breakdowns:
        - taxable_amount: 100.00
          tax_amount: 20.00
          tax_percent: 20.0
          tax_category: S
      totals:
        line_extension_amount: 100.00
        tax_exclusive_amount: 100.00
        tax_inclusive_amount: 120.00
        payable_amount: 120.00
        prepaid_amount: 0.00
    YAML
  end

  describe "#initialize" do
    it "loads default data when no file is given" do
      cfg = FacturX::Config.new
      expect(cfg.data["profile"]).to eq("EN16931")
      expect(cfg.data["seller"]["country_code"]).to eq("FR")
    end

    it "raises on missing file" do
      expect { FacturX::Config.new("/nonexistent.yaml") }.to raise_error(ArgumentError, /not found/)
    end
  end

  describe "#to_invoice_data" do
    it "converts config to InvoiceData" do
      Tempfile.create(["config", ".yaml"]) do |f|
        f.write(valid_yaml)
        f.close
        cfg = FacturX::Config.new(f.path)
        inv = cfg.to_invoice_data

        expect(inv).to be_a(FacturX::InvoiceData)
        expect(inv.profile).to eq("BASIC")
        expect(inv.number).to eq("TEST-001")
        expect(inv.seller[:name]).to eq("Test Seller")
        expect(inv.buyer[:name]).to eq("Test Buyer")
        expect(inv.issue_date).to eq(Date.new(2024, 1, 15))
        expect(inv.line_items.length).to eq(1)
        expect(inv.line_items.first[:price_amount]).to eq(100.00)
        expect(inv.valid?).to be true
      end
    end
  end

  describe "deep merge" do
    it "overrides nested values without destroying siblings" do
      yaml = <<~YAML
        seller:
          name: Override Name
      YAML

      Tempfile.create(["config", ".yaml"]) do |f|
        f.write(yaml)
        f.close
        cfg = FacturX::Config.new(f.path)
        expect(cfg.data["seller"]["name"]).to eq("Override Name")
        expect(cfg.data["seller"]["country_code"]).to eq("FR") # from defaults
        expect(cfg.overrides).to eq("seller" => { "name" => "Override Name" })
      end
    end
  end
end
