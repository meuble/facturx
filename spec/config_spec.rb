require 'spec_helper'

RSpec.describe Config do
  let(:default_config) { Config::DEFAULT_CONFIG }

  describe "#initialize" do
    it "loads default configuration when no file is provided" do
      config = Config.new
      expect(config.data).to eq(default_config)
    end

    it "loads custom configuration from YAML file" do
      custom_config = {
        'profil' => 'BASIC',
        'fournisseur' => {
          'nom' => 'CUSTOM SOCIETE',
          'siren' => '999999999'
        }
      }
      
      yaml_content = custom_config.to_yaml
      
      Tempfile.create(['config', '.yaml']) do |file|
        file.write(yaml_content)
        file.rewind
        
        config = Config.new(file.path)
        expect(config['profil']).to eq('BASIC')
        expect(config['fournisseur']['nom']).to eq('CUSTOM SOCIETE')
        expect(config['fournisseur']['siren']).to eq('999999999')
        # Default values should be preserved
        expect(config['client']['nom']).to eq(default_config['client']['nom'])
      end
    end

    it "handles missing config file gracefully" do
      config = Config.new('/nonexistent/path/config.yaml')
      expect(config.data).to eq(default_config)
    end

    it "handles invalid YAML gracefully" do
      Tempfile.create(['invalid', '.yaml']) do |file|
        file.write("invalid: yaml: content:")
        file.rewind
        
        expect {
          Config.new(file.path)
        }.to output(/Erreur de chargement/).to_stderr
      end
    end
  end

  describe "#[]" do
    let(:config) { Config.new }

    it "accesses top-level keys" do
      expect(config['profil']).to eq('EN16931')
    end

    it "accesses nested keys" do
      expect(config['fournisseur']['nom']).to eq('MA SOCIETE')
      expect(config['fournisseur']['siren']).to eq('123456789')
    end

    it "returns nil for unknown keys" do
      expect(config['unknown_key']).to be_nil
    end
  end

  describe "#method_missing" do
    let(:config) { Config.new }

    it "accesses keys as methods" do
      expect(config.profil).to eq('EN16931')
      expect(config.fournisseur).to eq(Config::DEFAULT_CONFIG['fournisseur'])
    end
  end

  describe "deep_merge" do
    it "merges nested hashes correctly" do
      target = {'a' => {'b' => 1, 'c' => 2}}
      source = {'a' => {'b' => 3, 'd' => 4}}
      
      config = Config.new
      result = config.send(:deep_merge, target, source)
      
      expect(result['a']['b']).to eq(3)  # Overwritten
      expect(result['a']['c']).to eq(2)  # Preserved
      expect(result['a']['d']).to eq(4)  # Added
    end

    it "concatenates arrays" do
      target = {'a' => [1, 2]}
      source = {'a' => [3, 4]}
      
      config = Config.new
      result = config.send(:deep_merge, target, source)
      
      expect(result['a']).to eq([1, 2, 3, 4])
    end
  end
end
