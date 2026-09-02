require 'spec_helper'
require_relative '../facturx_from_pdf'

RSpec.describe PDFDataExtractor do
  let(:sample_pdf_text) do
    <<~TEXT
      SOCIETE TEST SARL
      123 Rue de la Facture
      75001 PARIS
      FRANCE
      SIREN: 123456789
      TVA: FR123456789
      IBAN: FR7612345678901234567890123
      Email: contact@test.com
      Tel: +33123456789
      
      Facture n°: FACT-2024-001
      Date: 15/01/2024
      Échéance: 15/02/2024
      
      Client: CLIENT TEST
      321 Rue du Client
      75002 PARIS
      
      Désignation       Qté    P.U.    TVA    Montant
      Service test       2      100.00  20%    200.00
      Autre service      1      50.00   20%    50.00
      
      Total HT: 250.00
      TVA: 50.00
      Total TTC: 300.00
    TEXT
  end

  let(:extractor) do
    # Mock pdftotext to return our sample text
    allow_any_instance_of(described_class).to receive(:extract_text).and_return(sample_pdf_text)
    described_class.new('/fake/path.pdf')
  end

  describe '#extract_invoice_number' do
    it 'extracts invoice number from Facture n° pattern' do
      expect(extractor.extract_invoice_number).to eq('FACT-2024-001')
    end

    it 'extracts invoice number from FACTURE pattern' do
      text = "FACTURE N° INV-2024-002"
      allow_any_instance_of(described_class).to receive(:extract_text).and_return(text)
      extractor = described_class.new('/fake/path.pdf')
      expect(extractor.extract_invoice_number).to eq('INV-2024-002')
    end

    it 'returns default invoice number if not found' do
      text = "Some random text without invoice number"
      allow_any_instance_of(described_class).to receive(:extract_text).and_return(text)
      extractor = described_class.new('/fake/path.pdf')
      expect(extractor.extract_invoice_number).to match(/^FACT-\d{8}-001$/)
    end
  end

  describe '#extract_invoice_date' do
    it 'extracts date in DD/MM/YYYY format' do
      expect(extractor.extract_invoice_date).to eq('2024-01-15')
    end

    it 'extracts date in YYYY-MM-DD format' do
      text = "Date: 2024-01-15"
      allow_any_instance_of(described_class).to receive(:extract_text).and_return(text)
      extractor = described_class.new('/fake/path.pdf')
      expect(extractor.extract_invoice_date).to eq('2024-01-15')
    end

    it 'returns today date if not found' do
      text = "Some text without date"
      allow_any_instance_of(described_class).to receive(:extract_text).and_return(text)
      extractor = described_class.new('/fake/path.pdf')
      expect(extractor.extract_invoice_date).to eq(Date.today.strftime('%Y-%m-%d'))
    end
  end

  describe '#extract_due_date' do
    it 'extracts due date from Échéance pattern' do
      expect(extractor.extract_due_date).to eq('2024-02-15')
    end

    it 'calculates due date as 30 days after invoice date if not found' do
      text = "Facture n°: FACT-001\nDate: 01/01/2024"
      allow_any_instance_of(described_class).to receive(:extract_text).and_return(text)
      extractor = described_class.new('/fake/path.pdf')
      expect(extractor.extract_due_date).to eq('2024-01-31')
    end
  end

  describe '#extract_supplier' do
    it 'extracts supplier name' do
      expect(extractor.extract_supplier[:nom]).to eq('SOCIETE TEST SARL')
    end

    it 'extracts supplier address' do
      expect(extractor.extract_supplier[:adresse]).to include('123 Rue de la Facture')
    end

    it 'extracts supplier postal code' do
      expect(extractor.extract_supplier[:code_postal]).to eq('75001')
    end

    it 'extracts supplier city' do
      expect(extractor.extract_supplier[:ville]).to eq('PARIS')
    end

    it 'extracts supplier SIREN' do
      expect(extractor.extract_supplier[:siren]).to eq('123456789')
    end

    it 'extracts supplier VAT number' do
      expect(extractor.extract_supplier[:tva_intracommunautaire]).to eq('FR123456789')
    end

    it 'extracts supplier IBAN' do
      expect(extractor.extract_supplier[:iban]).to eq('FR7612345678901234567890123')
    end

    it 'extracts supplier email' do
      expect(extractor.extract_supplier[:email]).to eq('contact@test.com')
    end

    it 'extracts supplier phone' do
      expect(extractor.extract_supplier[:telephone]).to eq('+33123456789')
    end
  end

  describe '#extract_client' do
    it 'extracts client name' do
      expect(extractor.extract_client[:nom]).to eq('CLIENT TEST')
    end

    it 'extracts client address' do
      expect(extractor.extract_client[:adresse]).to include('321 Rue du Client')
    end
  end

  describe '#extract_line_items' do
    it 'extracts line items from table' do
      lines = extractor.extract_line_items
      expect(lines.size).to be >= 1
    end

    it 'extracts line item with description and price' do
      lines = extractor.extract_line_items
      expect(lines.first['description']).not_to be_empty
      expect(lines.first['prix_unitaire']).to be > 0
    end
  end

  describe '#extract_totals' do
    it 'extracts total HT' do
      totals = extractor.extract_totals
      expect(totals[:line_total]).to eq(250.0)
    end

    it 'extracts TVA amount' do
      totals = extractor.extract_totals
      expect(totals[:tax_total]).to eq(50.0)
    end

    it 'extracts grand total' do
      totals = extractor.extract_totals
      expect(totals[:grand_total]).to eq(300.0)
    end
  end

  describe '#extract_invoice_data' do
    it 'returns complete invoice data hash' do
      data = extractor.extract_invoice_data
      expect(data).to have_key(:numero)
      expect(data).to have_key(:date)
      expect(data).to have_key(:date_echeance)
      expect(data).to have_key(:fournisseur)
      expect(data).to have_key(:client)
      expect(data).to have_key(:lignes)
      expect(data).to have_key(:totaux)
    end
  end
end

RSpec.describe FacturXGenerator do
  let(:sample_pdf_text) do
    <<~TEXT
      SOCIETE TEST SARL
      123 Rue de la Facture
      75001 PARIS
      FRANCE
      SIREN: 123456789
      TVA: FR123456789
      
      Facture n°: FACT-2024-001
      Date: 15/01/2024
      Échéance: 15/02/2024
      
      Client: CLIENT TEST
      321 Rue du Client
      75002 PARIS
      
      Désignation       Qté    P.U.    TVA    Montant
      Service test       2      100.00  20%    200.00
      
      Total HT: 200.00
      TVA: 40.00
      Total TTC: 240.00
    TEXT
  end

  let(:extractor) do
    allow_any_instance_of(PDFDataExtractor).to receive(:extract_text).and_return(sample_pdf_text)
    PDFDataExtractor.new('/fake/path.pdf')
  end

  let(:invoice_data) { extractor.extract_invoice_data }
  let(:config) { Config.new }
  let(:generator) { FacturXGenerator.new(invoice_data, config) }

  describe '#initialize' do
    it 'accepts invoice data and config' do
      expect { FacturXGenerator.new(invoice_data, config) }.not_to raise_error
    end
  end

  describe '#generate_xml' do
    let(:xml_output) { generator.generate_xml }

    it 'generates valid XML' do
      expect { Nokogiri::XML(xml_output) }.not_to raise_error
    end

    it 'includes CrossIndustryInvoice root element' do
      doc = Nokogiri::XML(xml_output)
      expect(doc.at_xpath('//rsm:CrossIndustryInvoice')).not_to be_nil
    end

    it 'includes invoice number' do
      doc = Nokogiri::XML(xml_output)
      invoice_id = doc.at_xpath('//ram:ExchangedDocument/ram:ID')
      expect(invoice_id.text).to eq('FACT-2024-001')
    end

    it 'includes supplier name' do
      doc = Nokogiri::XML(xml_output)
      supplier_name = doc.at_xpath('//ram:SellerTradeParty/ram:Name')
      expect(supplier_name.text).to eq('SOCIETE TEST SARL')
    end

    it 'includes client name' do
      doc = Nokogiri::XML(xml_output)
      client_name = doc.at_xpath('//ram:BuyerTradeParty/ram:Name')
      expect(client_name.text).to eq('CLIENT TEST')
    end

    it 'includes line items' do
      doc = Nokogiri::XML(xml_output)
      line_items = doc.xpath('//ram:LineItem')
      expect(line_items.size).to be >= 1
    end

    it 'includes totals' do
      doc = Nokogiri::XML(xml_output)
      grand_total = doc.at_xpath('//ram:GrandTotalAmount')
      expect(grand_total).not_to be_nil
    end

    it 'includes correct GuidelineID for EN16931' do
      doc = Nokogiri::XML(xml_output)
      guideline = doc.at_xpath('//rsm:CrossIndustryInvoice')['GuidelineID']
      expect(guideline).to eq('urn:cen.eu:en16931:2017')
    end
  end

  describe '#save_xml' do
    it 'saves XML to file' do
      tempfile = Tempfile.new(['facturx_test', '.xml'])
      generator.save_xml(tempfile.path)
      expect(File.exist?(tempfile.path)).to be true
      expect(File.read(tempfile.path)).to include('CrossIndustryInvoice')
      tempfile.unlink
    end
  end
end

RSpec.describe FacturXFromPDFCLI do
  let(:sample_pdf_text) do
    <<~TEXT
      SOCIETE TEST SARL
      123 Rue de la Facture
      75001 PARIS
      
      Facture n°: FACT-TEST-001
      Date: 01/01/2024
      
      Client: TEST CLIENT
      
      Service test 1 2 100.00
      
      Total TTC: 240.00
    TEXT
  end

  before do
    # Mock pdftotext
    allow_any_instance_of(PDFDataExtractor).to receive(:extract_text).and_return(sample_pdf_text)
    
    # Mock qpdf
    allow_any_instance_of(FacturXIntegrator).to receive(:integrate_with_qpdf).and_return('/fake/output.pdf')
    
    # Create a temporary PDF file for testing
    @temp_pdf = Tempfile.new(['test_invoice', '.pdf'])
    File.write(@temp_pdf.path, 'PDF content')
  end

  after do
    @temp_pdf.unlink if @temp_pdf
  end

  describe '#parse_options' do
    it 'accepts PDF file argument' do
      cli = described_class.new
      allow(cli).to receive(:puts)
      allow(cli).to receive(:exit)
      
      # Mock ARGV
      original_argv = ARGV
      begin
        ARGV.replace([@temp_pdf.path])
        cli.parse_options
        expect(cli.instance_variable_get(:@pdf_path)).to eq(@temp_pdf.path)
      ensure
        ARGV.replace(original_argv)
      end
    end

    it 'accepts output option' do
      cli = described_class.new
      allow(cli).to receive(:puts)
      allow(cli).to receive(:exit)
      
      original_argv = ARGV
      begin
        ARGV.replace([@temp_pdf.path, '-o', '/output/path.pdf'])
        cli.parse_options
        expect(cli.instance_variable_get(:@options)[:output]).to eq('/output/path.pdf')
      ensure
        ARGV.replace(original_argv)
      end
    end

    it 'accepts profil option' do
      cli = described_class.new
      allow(cli).to receive(:puts)
      allow(cli).to receive(:exit)
      
      original_argv = ARGV
      begin
        ARGV.replace([@temp_pdf.path, '-p', 'BASIC'])
        cli.parse_options
        expect(cli.instance_variable_get(:@options)[:profil]).to eq('BASIC')
      ensure
        ARGV.replace(original_argv)
      end
    end

    it 'accepts config option' do
      cli = described_class.new
      allow(cli).to receive(:puts)
      allow(cli).to receive(:exit)
      
      original_argv = ARGV
      begin
        ARGV.replace([@temp_pdf.path, '-c', 'config.yaml'])
        cli.parse_options
        expect(cli.instance_variable_get(:@options)[:config]).to eq('config.yaml')
      ensure
        ARGV.replace(original_argv)
      end
    end

    it 'shows error when no PDF file provided' do
      cli = described_class.new
      original_argv = ARGV
      begin
        ARGV.replace([])
        expect { cli.parse_options }.to raise_error(SystemExit)
      ensure
        ARGV.replace(original_argv)
      end
    end

    it 'shows error when PDF file does not exist' do
      cli = described_class.new
      original_argv = ARGV
      begin
        ARGV.replace(['/nonexistent/file.pdf'])
        expect { cli.parse_options }.to raise_error(SystemExit)
      ensure
        ARGV.replace(original_argv)
      end
    end
  end
end
