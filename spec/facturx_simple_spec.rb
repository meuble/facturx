require 'spec_helper'

RSpec.describe "facturx_simple.rb" do
  describe "XML generation" do
    it "can load the script without executing it" do
      # Test that we can at least parse the script
      script_content = File.read(File.join(__dir__, '..', 'facturx_simple.rb'))
      expect(script_content).to include('Factur-X')
      expect(script_content).to include('zugpferd')
    end

    it "has correct usage message" do
      script_content = File.read(File.join(__dir__, '..', 'facturx_simple.rb'))
      expect(script_content).to include('Usage:')
      expect(script_content).to include('facture.pdf')
    end
  end

  describe "configuration defaults" do
    it "uses reasonable default values" do
      # Test that the script has sensible defaults
      script_content = File.read(File.join(__dir__, '..', 'facturx_simple.rb'))
      expect(script_content).to include('MA SOCIETE')
      expect(script_content).to include('EUR')
    end
  end
end
