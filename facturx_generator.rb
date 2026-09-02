#!/usr/bin/env ruby
# encoding: UTF-8

# =============================================================================
# Factur-X Generator pour Ruby
# 
# Ce script permet de:
# 1. Générer un XML Factur-X conforme EN 16931 (CII D22B)
# 2. Intégrer ce XML dans le PDF pour créer un fichier Factur-X
# 
# Dépendances: zugpferd, nokogiri
# 
# Installation:
#   bundle install
# 
# Utilisation:
#   ruby facturx_generator.rb facture.pdf [--config config.yaml]
#   ruby facturx_generator.rb facture.pdf --interactive
# 
# =============================================================================

require 'bundler/setup'
require 'zugpferd'
require 'nokogiri'
require 'yaml'
require 'date'
require 'optparse'
require 'fileutils'

# =============================================================================
# Configuration
# =============================================================================

class Config
  DEFAULT_CONFIG = {
    'profil' => 'EN16931',
    'fournisseur' => {
      'nom' => 'MA SOCIETE',
      'siren' => '123456789',
      'siret' => '12345678900010',
      'adresse' => '123 Rue de la Facture',
      'code_postal' => '75001',
      'ville' => 'PARIS',
      'pays' => 'FR',
      'telephone' => '+33123456789',
      'email' => 'contact@masociete.fr',
      'iban' => 'FR7612345678901234567890123',
      'bic' => 'BNPAFRPP',
      'tva_intracommunautaire' => 'FR123456789'
    },
    'client' => {
      'nom' => 'CLIENT TEST',
      'siren' => '987654321',
      'adresse' => '321 Rue du Client',
      'code_postal' => '75002',
      'ville' => 'PARIS',
      'pays' => 'FR'
    },
    'facture' => {
      'numero' => 'FACT-2024-001',
      'date' => Date.today.strftime('%Y-%m-%d'),
      'date_echeance' => (Date.today + 30).strftime('%Y-%m-%d'),
      'devise' => 'EUR',
      'conditions_reglement' => '30 jours net'
    },
    'lignes' => [
      {
        'description' => 'Service de consultation',
        'quantite' => 1,
        'prix_unitaire' => 100.00,
        'tva' => 20.0,
        'unite' => 'UN'
      },
      {
        'description' => 'Frais de dossier',
        'quantite' => 1,
        'prix_unitaire' => 50.00,
        'tva' => 20.0,
        'unite' => 'UN'
      }
    ],
    'pdf' => {
      'ghostscript_path' => '/usr/bin/gs',
      'resolution' => 300
    }
  }.freeze

  attr_reader :data

  def initialize(config_file = nil)
    @data = DEFAULT_CONFIG.dup
    
    if config_file && File.exist?(config_file)
      begin
        custom_config = YAML.load_file(config_file)
        @data = deep_merge(@data, custom_config || {})
      rescue => e
        warn "⚠️  Erreur de chargement du fichier de config: #{e.message}"
      end
    end
  end

  def [](key)
    @data[key]
  end

  def method_missing(name, *args)
    @data[name.to_s] || super
  end

  private

  def deep_merge(target, source)
    target.merge(source) do |key, old_val, new_val|
      if old_val.is_a?(Hash) && new_val.is_a?(Hash)
        deep_merge(old_val, new_val)
      elsif old_val.is_a?(Array) && new_val.is_a?(Array)
        old_val + new_val
      else
        new_val
      end
    end
  end
end

# =============================================================================
# Générateur XML Factur-X (CII D22B)
# =============================================================================

class FacturXGenerator
  # Namespaces CII D22B
  NS = {
    'rsm' => 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100',
    'ram' => 'urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100',
    'qdt' => 'urn:un:unece:uncefact:data:standard:QualifiedDataType:100',
    'udt' => 'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100'
  }.freeze

  # Guideline IDs pour chaque profil
  GUIDELINE_IDS = {
    'MINIMUM' => 'urn:factur-x.eu:1p0:minimum',
    'BASIC' => 'urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic',
    'EN16931' => 'urn:cen.eu:en16931:2017',
    'BASICWL' => 'urn:factur-x.eu:1p0:basicwl',
    'EXTENDED' => 'urn:factur-x.eu:1p0:extended'
  }.freeze

  def initialize(config)
    @config = config
  end

  # Génère le XML Factur-X
  def generate_xml
    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      xml['rsm'].CrossIndustryInvoice(
        'xmlns:rsm' => NS['rsm'],
        'xmlns:ram' => NS['ram'],
        'xmlns:qdt' => NS['qdt'],
        'xmlns:udt' => NS['udt'],
        'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation' => 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100 CrossIndustryInvoice_100pD22B.xsd',
        'GuidelineID' => GUIDELINE_IDS[@config['profil'].upcase] || GUIDELINE_IDS['EN16931']
      ) do
        # En-tête du document
        xml['ram'].ExchangedDocument do
          xml['ram'].ID @config['facture']['numero']
          xml['ram'].TypeCode '380' # 380 = Facture
          xml['ram'].IssueDateTime do
            xml['udt'].DateTimeString(@config['facture']['date'].gsub('-', ''), format: '102')
          end
        end

        # Transaction commerciale
        xml['ram'].SupplyChainTradeTransaction do
          # Accord commercial (en-tête)
          xml['ram'].ApplicableHeaderTradeAgreement do
            # Vendeur (fournisseur)
            xml['ram'].SellerTradeParty do
              xml['ram'].Name @config['fournisseur']['nom']
              xml['ram'].PostalTradeAddress do
                xml['ram'].PostcodeCode @config['fournisseur']['code_postal']
                xml['ram'].LineOne @config['fournisseur']['adresse']
                xml['ram'].CityName @config['fournisseur']['ville']
                xml['ram'].CountryID @config['fournisseur']['pays']
              end
              
              # Identifiants fiscaux
              xml['ram'].SpecifiedTaxRegistration do
                xml['ram'].ID(@config['fournisseur']['siren'], schemeID: 'FC')
              end
              
              if @config['fournisseur']['tva_intracommunautaire']
                xml['ram'].SpecifiedTaxRegistration do
                  xml['ram'].ID(@config['fournisseur']['tva_intracommunautaire'], schemeID: 'VA')
                end
              end
              
              # Coordonnées
              if @config['fournisseur']['telephone']
                xml['ram'].URIUniversalCommunication do
                  xml['ram'].URIID(@config['fournisseur']['telephone'], schemeID: '09')
                end
              end
              
              if @config['fournisseur']['email']
                xml['ram'].URIUniversalCommunication do
                  xml['ram'].URIID(@config['fournisseur']['email'], schemeID: 'EM')
                end
              end
            end

            # Acheteur (client)
            xml['ram'].BuyerTradeParty do
              xml['ram'].Name @config['client']['nom']
              xml['ram'].PostalTradeAddress do
                xml['ram'].PostcodeCode @config['client']['code_postal']
                xml['ram'].LineOne @config['client']['adresse']
                xml['ram'].CityName @config['client']['ville']
                xml['ram'].CountryID @config['client']['pays']
              end
              
              if @config['client']['siren']
                xml['ram'].SpecifiedTaxRegistration do
                  xml['ram'].ID(@config['client']['siren'], schemeID: 'FC')
                end
              end
            end

            # Conditions de règlement
            xml['ram'].ApplicableTradePaymentTerms do
              xml['ram'].Description @config['facture']['conditions_reglement']
            end
          end

          # Règlement
          xml['ram'].ApplicableHeaderTradeSettlement do
            xml['ram'].InvoiceCurrencyCode @config['facture']['devise']
            
            # IBAN du fournisseur
            if @config['fournisseur']['iban']
              xml['ram'].PayeeTradeParty do
                xml['ram'].SpecifiedTradeAccountingAccount do
                  xml['ram'].ID(@config['fournisseur']['iban'], schemeID: 'IBAN')
                end
              end
            end
            
            # BIC du fournisseur
            if @config['fournisseur']['bic']
              xml['ram'].PayeeTradeParty do
                xml['ram'].SpecifiedTradeAccountingAccount do
                  xml['ram'].ServiceProviderID(@config['fournisseur']['bic'], schemeID: 'BIC')
                end
              end
            end
            
            # Date d'échéance
            xml['ram'].ApplicableTradePaymentTerms do
              xml['ram'].DueDateTime do
                xml['udt'].DateTimeString(@config['facture']['date_echeance'].gsub('-', ''), format: '102')
              end
            end
          end

          # Lignes de facture
          xml['ram'].ApplicableHeaderTradeDelivery do
            xml['ram'].BilledDelivery do
              @config['lignes'].each_with_index do |ligne, index|
                xml['ram'].DeliveryItem do
                  xml['ram'].AssociatedDocumentLineDocument do
                    xml['ram'].LineID index + 1
                  end
                  xml['ram'].Note ligne['description']
                end
              end
            end
          end

          # Settlement (lignes et totaux)
          xml['ram'].ApplicableHeaderTradeSettlement do
            xml['ram'].SpecifiedTradeSettlementMonetarySummation do
              # Calcul des totaux
              total_ht = 0
              total_tva = 0
              
              @config['lignes'].each do |ligne|
                montant_ht = ligne['quantite'] * ligne['prix_unitaire']
                total_ht += montant_ht
                
                montant_tva = montant_ht * (ligne['tva'] / 100.0)
                total_tva += montant_tva
              end
              
              total_ttc = total_ht + total_tva
              
              xml['ram'].LineTotalAmount(total_ht.round(2), currencyID: @config['facture']['devise'])
              xml['ram'].TaxBasisTotalAmount(total_ht.round(2), currencyID: @config['facture']['devise'])
              xml['ram'].TaxTotalAmount(total_tva.round(2), currencyID: @config['facture']['devise'])
              xml['ram'].GrandTotalAmount(total_ttc.round(2), currencyID: @config['facture']['devise'])
              xml['ram'].TotalPrepaidAmount(0, currencyID: @config['facture']['devise'])
              xml['ram'].AmountDue(total_ttc.round(2), currencyID: @config['facture']['devise'])
            end

            # Détail des taxes (TVA)
            # Regrouper par taux de TVA
            tva_groups = @config['lignes'].group_by { |l| l['tva'] }
            tva_groups.each do |taux, lignes|
              montant_ht = lignes.sum { |l| l['quantite'] * l['prix_unitaire'] }
              montant_tva = montant_ht * (taux / 100.0)
              
              xml['ram'].ApplicableTradeTax do
                xml['ram'].CalculatedTradeTax do
                  xml['ram'].BasisAmount(montant_ht.round(2), currencyID: @config['facture']['devise'])
                  xml['ram'].TypeCode 'VAT'
                  xml['ram'].CategoryCode 'S' # Standard rate
                  xml['ram'].ExemptionReasonCode 'VAT'
                  xml['ram'].ApplicableTradeTaxRate do
                    xml['ram'].Percent taux
                  end
                  xml['ram'].CalculatedTradeTaxAmount(montant_tva.round(2), currencyID: @config['facture']['devise'])
                end
              end
            end
          end

          # Lignes de facture détaillées
          xml['ram'].SpecifiedSupplyChainTradeLineItem do
            @config['lignes'].each_with_index do |ligne, index|
              montant_ht = ligne['quantite'] * ligne['prix_unitaire']
              montant_tva = montant_ht * (ligne['tva'] / 100.0)
              
              xml['ram'].LineItem do
                xml['ram'].AssociatedDocumentLineDocument do
                  xml['ram'].LineID index + 1
                end
                xml['ram'].Note ligne['description']
                xml['ram'].BilledQuantity(ligne['quantite'], unitCode: ligne['unite'])
                xml['ram'].NetPriceProductTradePrice do
                  xml['ram'].ChargeAmount(montant_ht.round(2), currencyID: @config['facture']['devise'])
                  xml['ram'].BasisQuantity(ligne['quantite'], unitCode: ligne['unite'])
                end
                
                # TVA par ligne
                xml['ram'].ApplicableTradeTax do
                  xml['ram'].CalculatedTradeTax do
                    xml['ram'].BasisAmount(montant_ht.round(2), currencyID: @config['facture']['devise'])
                    xml['ram'].TypeCode 'VAT'
                    xml['ram'].CategoryCode 'S'
                    xml['ram'].ExemptionReasonCode 'VAT'
                    xml['ram'].ApplicableTradeTaxRate do
                      xml['ram'].Percent ligne['tva']
                    end
                    xml['ram'].CalculatedTradeTaxAmount(montant_tva.round(2), currencyID: @config['facture']['devise'])
                  end
                end
              end
            end
          end
        end
      end
    end

    builder.to_xml
  end

  # Sauvegarde le XML dans un fichier
  def save_xml(filepath)
    xml_content = generate_xml
    File.write(filepath, xml_content)
    filepath
  end
end

# =============================================================================
# Intégrateur Factur-X (PDF + XML)
# =============================================================================

class FacturXIntegrator
  def initialize(config)
    @config = config
  end

  # Intègre le XML dans le PDF pour créer un Factur-X
  def integrate(pdf_path, xml_path, output_path = nil)
    output_path ||= pdf_path.sub(/\.pdf$/i, '_facturx.pdf')
    
    # Lire le XML
    xml_content = File.read(xml_path)
    
    # Utiliser zugpferd pour créer le PDF/A-3 avec XML embarqué
    begin
      # Créer un document CII à partir du XML
      invoice = Zugpferd::CII::Reader.new.read(xml_content)
      
      # Créer l'embedding
      embedder = Zugpferd::PDF::Embedder.new
      
      # Options pour l'embedding
      options = {
        pdf_path: pdf_path,
        xml: xml_content,
        output_path: output_path,
        version: '2p1', # Version Factur-X/ZUGFeRD
        conformance_level: 'EN 16931'
      }
      
      # Embarquer le XML dans le PDF
      embedder.embed(options)
      
      puts "✅ Factur-X créé avec succès: #{output_path}"
      output_path
      
    rescue => e
      # Si zugpferd échoue, essayer avec qpdf (méthode alternative)
      puts "⚠️  zugpferd a échoué, tentative avec qpdf..."
      integrate_with_qpdf(pdf_path, xml_path, output_path)
    end
  end

  # Méthode alternative avec qpdf
  def integrate_with_qpdf(pdf_path, xml_path, output_path)
    require 'open3'
    
    # Vérifier que qpdf est installé
    unless system('which qpdf > /dev/null 2>&1')
      raise "❌ qpdf n'est pas installé. Installez-le avec:\n  sudo apt-get install qpdf  # Debian/Ubuntu\n  brew install qpdf          # macOS"
    end
    
    # Commande qpdf pour ajouter une pièce jointe
    cmd = "qpdf --add-attachment #{xml_path} -- #{pdf_path} #{output_path}"
    
    stdout, stderr, status = Open3.capture3(cmd)
    
    # qpdf peut réussir même avec des warnings, donc on vérifie que le fichier a été créé
    if File.exist?(output_path) && File.size(output_path) > 0
      # Vérifier que l'attachement a été ajouté
      if system("qpdf --list-attachments #{output_path} > /dev/null 2>&1")
        puts "✅ Factur-X créé avec qpdf: #{output_path}"
        output_path
      else
        puts "⚠️  Factur-X créé mais vérification de l'attachement échouée: #{output_path}"
        output_path
      end
    else
      raise "❌ Échec de qpdf: #{stderr}"
    end
  end
end

# =============================================================================
# Interface utilisateur
# =============================================================================

class FacturXCLI
  def initialize
    @config = nil
    @options = {}
    parse_options
  end

  def parse_options
    OptionParser.new do |opts|
      opts.banner = "Usage: ruby facturx_generator.rb PDF [options]"
      
      opts.on("-c", "--config FILE", "Fichier de configuration YAML") do |file|
        @options[:config] = file
      end
      
      opts.on("-i", "--interactive", "Mode interactif") do |i|
        @options[:interactive] = i
      end
      
      opts.on("-o", "--output FILE", "Fichier PDF de sortie") do |file|
        @options[:output] = file
      end
      
      opts.on("-p", "--profil PROFIL", "Profil Factur-X (MINIMUM, BASIC, EN16931, EXTENDED)") do |profil|
        @options[:profil] = profil.upcase
      end
      
      opts.on("-h", "--help", "Affiche cette aide") do
        puts opts
        exit
      end
    end.parse!
    
    # Vérifier qu'un fichier PDF est fourni
    if ARGV.empty?
      puts "❌ Erreur: Veuillez spécifier un fichier PDF"
      puts "Exemple: ruby facturx_generator.rb facture.pdf"
      exit 1
    end
    
    @pdf_path = ARGV[0]
    
    unless File.exist?(@pdf_path)
      puts "❌ Erreur: Fichier introuvable: #{@pdf_path}"
      exit 1
    end
  end

  def run
    # Charger la configuration
    @config = Config.new(@options[:config])
    
    # Appliquer les options de la ligne de commande
    if @options[:profil]
      @config.data['profil'] = @options[:profil]
    end
    
    # Mode interactif
    if @options[:interactive]
      interactive_mode
    end
    
    # Générer le nom du fichier XML
    xml_path = @pdf_path.sub(/\.pdf$/i, '.xml')
    
    # Générer le nom du fichier de sortie
    output_path = @options[:output] || @pdf_path.sub(/\.pdf$/i, '_facturx.pdf')
    
    puts "=" * 60
    puts "📄 Factur-X Generator"
    puts "=" * 60
    puts "PDF source: #{@pdf_path}"
    puts "Profil: #{@config['profil']}"
    puts "Fichier XML: #{xml_path}"
    puts "Sortie: #{output_path}"
    puts ""
    
    # Générer le XML
    puts "🔄 Génération du XML Factur-X..."
    generator = FacturXGenerator.new(@config)
    generator.save_xml(xml_path)
    puts "✅ XML généré: #{xml_path}"
    
    # Intégrer dans le PDF
    puts "🔄 Intégration du XML dans le PDF..."
    integrator = FacturXIntegrator.new(@config)
    integrator.integrate(@pdf_path, xml_path, output_path)
    
    puts ""
    puts "=" * 60
    puts "✅ Succès! Factur-X créé: #{output_path}"
    puts "=" * 60
    puts ""
    puts "Vérification:"
    puts "  - Ouvrez le fichier avec Adobe Acrobat Reader"
    puts "  - Vérifiez que 'factur-x.xml' est présent dans les pièces jointes"
    puts "  - Utilisez le validateur: https://e-invoice.be/blog/factur-x-format"
    puts ""
    
    # Nettoyer le fichier XML temporaire
    # File.delete(xml_path) if File.exist?(xml_path)
  end

  def interactive_mode
    puts "=" * 60
    puts "📝 Mode interactif - Configuration de la facture"
    puts "=" * 60
    puts ""
    
    # Fournisseur
    @config.data['fournisseur']['nom'] = ask("Nom du fournisseur", @config['fournisseur']['nom'])
    @config.data['fournisseur']['siren'] = ask("SIREN du fournisseur", @config['fournisseur']['siren'])
    @config.data['fournisseur']['adresse'] = ask("Adresse du fournisseur", @config['fournisseur']['adresse'])
    @config.data['fournisseur']['code_postal'] = ask("Code postal du fournisseur", @config['fournisseur']['code_postal'])
    @config.data['fournisseur']['ville'] = ask("Ville du fournisseur", @config['fournisseur']['ville'])
    @config.data['fournisseur']['pays'] = ask("Pays du fournisseur (FR, BE, etc.)", @config['fournisseur']['pays'])
    @config.data['fournisseur']['email'] = ask("Email du fournisseur", @config['fournisseur']['email'])
    @config.data['fournisseur']['iban'] = ask("IBAN du fournisseur", @config['fournisseur']['iban'])
    @config.data['fournisseur']['bic'] = ask("BIC du fournisseur", @config['fournisseur']['bic'])
    
    # Client
    @config.data['client']['nom'] = ask("Nom du client", @config['client']['nom'])
    @config.data['client']['adresse'] = ask("Adresse du client", @config['client']['adresse'])
    @config.data['client']['code_postal'] = ask("Code postal du client", @config['client']['code_postal'])
    @config.data['client']['ville'] = ask("Ville du client", @config['client']['ville'])
    @config.data['client']['pays'] = ask("Pays du client (FR, BE, etc.)", @config['client']['pays'])
    
    # Facture
    @config.data['facture']['numero'] = ask("Numéro de facture", @config['facture']['numero'])
    @config.data['facture']['date'] = ask("Date de facture (AAAA-MM-JJ)", @config['facture']['date'])
    @config.data['facture']['date_echeance'] = ask("Date d'échéance (AAAA-MM-JJ)", @config['facture']['date_echeance'])
    
    # Lignes de facture
    puts ""
    puts "Lignes de facture:"
    @config.data['lignes'] = []
    
    loop do
      puts ""
      description = ask("Description de la ligne (laisser vide pour terminer)")
      break if description.to_s.strip.empty?
      
      quantite = ask("Quantité", 1).to_f
      prix_unitaire = ask("Prix unitaire (ex: 100.00)", 0.0).to_f
      tva = ask("Taux de TVA (ex: 20.0)", 20.0).to_f
      unite = ask("Unité (ex: UN, H, KG)", "UN")
      
      @config.data['lignes'] << {
        'description' => description,
        'quantite' => quantite,
        'prix_unitaire' => prix_unitaire,
        'tva' => tva,
        'unite' => unite
      }
      
      puts "✅ Ligne ajoutée: #{description} - #{quantite} x #{prix_unitaire}€ (TVA: #{tva}%)"
    end
    
    # Profil
    @config.data['profil'] = ask("Profil Factur-X (MINIMUM, BASIC, EN16931, EXTENDED)", @config['profil'])
    
    puts ""
  end

  private

  def ask(prompt, default_value = nil)
    print "#{prompt}: "
    if default_value
      print "[#{default_value}] "
    end
    
    input = gets.chomp
    
    if input.empty? && default_value
      default_value
    else
      input
    end
  end
end

# =============================================================================
# Point d'entrée principal
# =============================================================================

if __FILE__ == $0
  begin
    cli = FacturXCLI.new
    cli.run
  rescue => e
    puts "❌ Erreur: #{e.message}"
    puts e.backtrace.first(5).join("\n") if e.backtrace
    exit 1
  end
end
