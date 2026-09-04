# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "Integration" do
  let(:valid_data) do
    FacturX::InvoiceData.new(
      profile: "EN16931",
      number: "INT-001",
      issue_date: Date.new(2026, 1, 15),
      due_date: Date.new(2026, 2, 15),
      currency_code: "EUR",
      seller: {
        name: "Seller Co",
        legal_registration_id: "123456789",
        vat_identifier: "FR123456789",
        postal_zone: "75001",
        street_name: "1 Rue Test",
        city_name: "PARIS",
        country_code: "FR",
        iban: "FR7630006000011234567890189"
      },
      buyer: {
        name: "Buyer Co",
        vat_identifier: "FR987654321",
        country_code: "FR",
        electronic_address: "987654321",
        electronic_address_scheme: "0225"
      },
      legal_notes: {
        "PMT" => "Recovery fee: 40 EUR",
        "PMD" => "Late payment interest applies",
        "AAB" => "No early payment discount"
      },
      line_items: [
        {
          id: "1", name: "Service", description: "Dev work",
          quantity: 2, unit_code: "C62", price_amount: 500.00,
          line_total_amount: 1000.00, tax_percent: 20.0, tax_category: "S"
        }
      ],
      tax_breakdowns: [
        { taxable_amount: 1000.00, tax_amount: 200.00, tax_percent: 20.0, tax_category: "S" }
      ],
      line_extension_amount: 1000.00,
      tax_exclusive_amount: 1000.00,
      tax_inclusive_amount: 1200.00,
      payable_amount: 1200.00,
      prepaid_amount: 0.00
    )
  end

  let(:sample_pdf) do
    # Create a minimal PDF using hexapdf for testing
    require "hexapdf"
    tmp = Tempfile.new(["sample", ".pdf"])
    doc = HexaPDF::Document.new
    page = doc.pages.add
    page.canvas.font("Helvetica", size: 12)
    page.canvas.text("Sample Invoice", at: [100, 700])
    doc.write(tmp.path)
    doc = nil
    tmp.path
  end

  after do
    File.delete(sample_pdf) if File.exist?(sample_pdf)
  end

  it "generates a valid Factur-X PDF from InvoiceData" do
    output = Tempfile.new(["output", ".pdf"])
    begin
      FacturX.generate(
        input_pdf: sample_pdf,
        output_pdf: output.path,
        data: valid_data
      )

      expect(File).to exist(output.path)
      expect(File.size(output.path)).to be > 0

      # Structural verification
      doc = HexaPDF::Document.open(output.path)
      expect(doc.catalog.key?(:Names)).to be true
      expect(doc.catalog.key?(:AF)).to be true
      expect(doc.catalog.key?(:Metadata)).to be true
      expect(doc.catalog.key?(:OutputIntents)).to be true

      ef_tree = doc.catalog.names[:EmbeddedFiles]
      expect(ef_tree).not_to be_nil
      expect(ef_tree).to be_a(HexaPDF::NameTreeNode)

      arr = ef_tree[:Names]
      expect(arr.to_a.length).to eq(2)
      expect(arr.to_a[0]).to eq("factur-x.xml")

      filespec = arr.to_a[1]
      expect(filespec[:Type]).to eq(:Filespec)
      expect(filespec[:AF]).to eq(:Alternative)

      ef = filespec[:EF][:F]
      expect(filespec[:EF][:UF]).to eq(ef)
      expect(ef[:Subtype]).to eq(:"application#2Fxml")
      expect(ef[:Params][:Size]).to eq(ef.stream.bytesize)
      expect(ef.stream).to include("CrossIndustryInvoice")
      expect(ef.stream).to include("Seller Co")
      expect(ef.stream).to include("INT-001")
    ensure
      output.close!
    end
  end

  it "generates a valid Factur-X PDF from config file" do
    yaml = <<~YAML
      profile: BASIC
      seller:
        name: Config Seller
        vat_identifier: FR111111111
        country_code: FR
      buyer:
        name: Config Buyer
        country_code: FR
        electronic_address: "111111111"
        electronic_address_scheme: "0225"
      invoice:
        legal_notes:
          PMT: "Recovery fee: 40 EUR"
          PMD: "Late payment interest applies"
          AAB: "No early payment discount"
        number: CFG-001
        issue_date: "2024-06-01"
        due_date: "2024-07-01"
      line_items:
        - id: "1"
          name: Item
          quantity: 1
          unit_code: C62
          price_amount: 200.00
          line_total_amount: 200.00
          tax_percent: 20.0
          tax_category: S
      tax_breakdowns:
        - taxable_amount: 200.00
          tax_amount: 40.00
          tax_percent: 20.0
          tax_category: S
      totals:
        line_extension_amount: 200.00
        tax_exclusive_amount: 200.00
        tax_inclusive_amount: 240.00
        payable_amount: 240.00
        prepaid_amount: 0.00
    YAML

    output = Tempfile.new(["output", ".pdf"])
    config_file = Tempfile.new(["config", ".yaml"])
    begin
      config_file.write(yaml)
      config_file.close

      FacturX.generate(
        input_pdf: sample_pdf,
        output_pdf: output.path,
        config_path: config_file.path
      )

      expect(File).to exist(output.path)
      expect(File.size(output.path)).to be > 0

      doc = HexaPDF::Document.open(output.path)
      ef = doc.catalog.names[:EmbeddedFiles][:Names].to_a[1][:EF][:F]
      expect(ef.stream).to include("Config Seller")
      expect(ef.stream).to include("CFG-001")
    ensure
      output.close!
      config_file.close!
    end
  end

  it "emits payment terms when they are provided" do
    data = valid_data
    data.seller = data.seller.reject { |key, _value| key == :iban }
    data.payment_terms = "Payable within 30 days"

    xml = FacturX::XmlGenerator.new(data).generate

    expect(xml).to include("Payable within 30 days")
  end

  it "normalizes a buyer SIRET and scopes the French scheme to legal registration" do
    data = valid_data
    data.buyer[:legal_registration_id] = "98765432100012"

    xml = FacturX::XmlGenerator.new(data).generate
    buyer = Nokogiri::XML(xml).at("//ram:BuyerTradeParty")

    expect(buyer.at("./ram:ID").text).to eq("987654321")
    expect(buyer.at("./ram:ID").attr("schemeID")).to be_nil
    expect(buyer.at("./ram:SpecifiedLegalOrganization/ram:ID").attr("schemeID")).to eq("0002")
  end
end
