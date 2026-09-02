require 'spec_helper'

RSpec.describe FacturXGenerator do
  let(:config) do
    config_data = Config::DEFAULT_CONFIG.dup
    config_data['facture']['numero'] = 'TEST-001'
    config_data['facture']['date'] = '2024-01-01'
    config_data['facture']['date_echeance'] = '2024-01-31'
    config_data['lignes'] = [
      {
        'description' => 'Test Service',
        'quantite' => 2,
        'prix_unitaire' => 50.00,
        'tva' => 20.0,
        'unite' => 'UN'
      }
    ]
    Config.new.tap { |c| c.instance_variable_set(:@data, config_data) }
  end

  let(:generator) { FacturXGenerator.new(config) }

  describe "#initialize" do
    it "accepts a config object" do
      expect { FacturXGenerator.new(config) }.not_to raise_error
    end
  end

  describe "#generate_xml" do
    let(:xml_output) { generator.generate_xml }

    it "generates valid XML" do
      expect { Nokogiri::XML(xml_output) }.not_to raise_error
    end

    it "includes CrossIndustryInvoice root element" do
      doc = Nokogiri::XML(xml_output)
      expect(doc.at_xpath('//rsm:CrossIndustryInvoice')).not_to be_nil
    end

    it "includes correct namespaces" do
      doc = Nokogiri::XML(xml_output)
      root = doc.at_xpath('//rsm:CrossIndustryInvoice')
      
      expect(root.namespaces.key?('xmlns:rsm')).to be true
      expect(root.namespaces.key?('xmlns:ram')).to be true
      expect(root.namespaces.key?('xmlns:udt')).to be true
    end

    it "includes GuidelineID attribute" do
      expect(xml_output).to include('GuidelineID="urn:cen.eu:en16931:2017"')
    end

    it "includes invoice number" do
      expect(xml_output).to include('TEST-001')
    end

    it "includes invoice date" do
      expect(xml_output).to include('20240101')
    end

    it "includes seller information" do
      expect(xml_output).to include('MA SOCIETE')
      expect(xml_output).to include('123456789')
    end

    it "includes buyer information" do
      expect(xml_output).to include('CLIENT TEST')
    end

    it "includes line items" do
      expect(xml_output).to include('Test Service')
      expect(xml_output).to include('2')
      expect(xml_output).to include('100.0') # prix_unitaire * quantite = 50 * 2 = 100
    end

    it "calculates correct totals" do
      # 2 * 50 = 100 HT, 100 * 0.2 = 20 TVA, 120 TTC
      expect(xml_output).to include('100.0')
      expect(xml_output).to include('20.0')
      expect(xml_output).to include('120.0')
    end

    it "includes VAT information" do
      expect(xml_output).to include('VAT')
      expect(xml_output).to include('20.0')
    end

    it "includes currency information" do
      expect(xml_output).to include('EUR')
    end

    it "generates XML with correct structure" do
      doc = Nokogiri::XML(xml_output)
      
      # Check main elements exist
      expect(doc.at_xpath('//rsm:CrossIndustryInvoice/ram:ExchangedDocument')).not_to be_nil
      expect(doc.at_xpath('//rsm:CrossIndustryInvoice/ram:SupplyChainTradeTransaction')).not_to be_nil
      expect(doc.at_xpath('//rsm:CrossIndustryInvoice/ram:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement')).not_to be_nil
    end
  end

  describe "#save_xml" do
    it "saves XML to file" do
      Tempfile.create(['facturx', '.xml']) do |file|
        result = generator.save_xml(file.path)
        
        expect(File.exist?(file.path)).to be true
        expect(result).to eq(file.path)
        
        content = File.read(file.path)
        expect(content).to include('CrossIndustryInvoice')
      end
    end
  end

  describe "with different profiles" do
    it "generates XML with MINIMUM profile" do
      config.data['profil'] = 'MINIMUM'
      xml = generator.generate_xml
      expect(xml).to include('urn:factur-x.eu:1p0:minimum')
    end

    it "generates XML with BASIC profile" do
      config.data['profil'] = 'BASIC'
      xml = generator.generate_xml
      expect(xml).to include('urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic')
    end

    it "generates XML with EXTENDED profile" do
      config.data['profil'] = 'EXTENDED'
      xml = generator.generate_xml
      expect(xml).to include('urn:factur-x.eu:1p0:extended')
    end
  end

  describe "with empty lines" do
    it "handles empty lines array" do
      config.data['lignes'] = []
      xml = generator.generate_xml
      
      expect { Nokogiri::XML(xml) }.not_to raise_error
      expect(xml).to include('>0<') # Totals should be 0 (integer)
    end
  end

  describe "with multiple lines" do
    it "calculates totals correctly for multiple lines" do
      config.data['lignes'] = [
        {'description' => 'Item 1', 'quantite' => 1, 'prix_unitaire' => 100.0, 'tva' => 20.0, 'unite' => 'UN'},
        {'description' => 'Item 2', 'quantite' => 2, 'prix_unitaire' => 50.0, 'tva' => 10.0, 'unite' => 'UN'}
      ]
      
      xml = generator.generate_xml
      # Item 1: 100 HT + 20 TVA = 120
      # Item 2: 100 HT + 10 TVA = 110
      # Total: 200 HT + 30 TVA = 230
      expect(xml).to include('200.0')
      expect(xml).to include('230.0')
    end
  end
end
