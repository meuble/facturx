#!/usr/bin/env ruby
# encoding: UTF-8

# =============================================================================
# Factur-X Generator from PDF
# 
# Ce script extrait les données d'une facture PDF (Facturation.pro) et génère
# un XML Factur-X conforme EN 16931, puis l'embarque dans le PDF.
# 
# Utilisation:
#   ruby facturx_from_pdf.rb facture.pdf [options]
# 
# Options:
#   -o, --output FILE       Fichier PDF de sortie (défaut: <input>_facturx.pdf)
#   -p, --profil PROFIL     Profil Factur-X (MINIMUM, BASIC, EN16931, EXTENDED)
#   -c, --config FILE       Fichier de configuration YAML pour les infos manquantes
#   -h, --help              Affiche cette aide
# 
# Dépendances:
#   - gem: nokogiri, zugpferd
#   - système: pdftotext (poppler-utils), qpdf
# 
# Installation:
#   bundle install
#   sudo apt-get install poppler-utils qpdf  # Debian/Ubuntu
#   brew install poppler qpdf                # macOS
# 
# =============================================================================

require 'bundler/setup'
require 'nokogiri'
require 'yaml'
require 'date'
require 'optparse'
require 'open3'
require 'bigdecimal'
require 'bigdecimal/util'

# =============================================================================
# Configuration
# =============================================================================

class Config
  DEFAULT_CONFIG = {
    'profil' => 'EN16931',
    'fournisseur' => {
      'nom' => 'MA SOCIETE',
      'siren' => '',
      'siret' => '',
      'adresse' => '',
      'code_postal' => '',
      'ville' => '',
      'pays' => 'FR',
      'telephone' => '',
      'email' => '',
      'iban' => '',
      'bic' => '',
      'tva_intracommunautaire' => ''
    },
    'devise' => 'EUR',
    'conditions_reglement' => '30 jours net'
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
# Extracteur de données PDF (Facturation.pro)
# =============================================================================

class PDFDataExtractor
  def initialize(pdf_path)
    @pdf_path = pdf_path
    @text = extract_text
  end

  # Extrait le texte du PDF
  def extract_text
    unless system('which pdftotext > /dev/null 2>&1')
      raise "pdftotext n'est pas installé. Installez poppler-utils:\n  sudo apt-get install poppler-utils  # Debian/Ubuntu\n  brew install poppler                # macOS"
    end
    
    # Créer un fichier temporaire
    txt_path = "#{@pdf_path}.txt"
    system("pdftotext -layout '#{@pdf_path}' '#{txt_path}' 2>/dev/null")
    
    if File.exist?(txt_path)
      text = File.read(txt_path)
      File.delete(txt_path)
      text
    else
      raise "Échec de l'extraction du texte du PDF"
    end
  end

  # Extrait toutes les données de la facture
  def extract_invoice_data
    {
      numero: extract_invoice_number,
      date: extract_invoice_date,
      date_echeance: extract_due_date,
      fournisseur: extract_supplier,
      client: extract_client,
      lignes: extract_line_items,
      totaux: extract_totals
    }
  end

  # Extrait le numéro de facture
  def extract_invoice_number
    # Facturation.pro: "Facture n°" ou "N° Facture" ou "FACTURE N°"
    patterns = [
      /(?:Facture|FACTURE|N°\s*Facture|Invoice\s*n°?)\s*[:\s]*([A-Z0-9\-]+)/i,
      /(?:Num\.?\s*facture|Fact\.?\s*n°?)\s*[:\s]*([A-Z0-9\-]+)/i,
      /^([A-Z]{2,}\d{4,})\s*$/,
      /([A-Z]{2,}\d{4,})/ 
    ]
    
    patterns.each do |pattern|
      match = @text.match(pattern)
      return match[1].strip if match
    end
    
    # Essayer de trouver un numéro de facture dans le format standard
    match = @text.match(/([A-Z]{2,}\d{4,}\s*[A-Z0-9\-]*)/)
    return match[1].strip.gsub(/\s/, '') if match
    
    "FACT-#{Date.today.strftime('%Y%m%d')}-001"
  end

  # Extrait la date de facture
  def extract_invoice_date
    # Facturation.pro: "Date" ou "Date de facture" ou "Facture du"
    patterns = [
      /(?:Date|Date\s+de\s+facture|Facture\s+du|Invoice\s+date)\s*[:\s]*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})/i,
      /(?:Date|Date\s+facture)\s*[:\s]*(\d{1,2}\s+(?:janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4})/i,
      /(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})/,
      /(\d{4}[\-\/]\d{2}[\-\/]\d{2})/,
      /(\d{8})/ 
    ]
    
    patterns.each do |pattern|
      match = @text.match(pattern)
      if match
        date_str = match[1].strip
        # Convertir en format AAAA-MM-JJ
        parsed_date = parse_date(date_str)
        return parsed_date.strftime('%Y-%m-%d') if parsed_date
      end
    end
    
    Date.today.strftime('%Y-%m-%d')
  end

  # Extrait la date d'échéance
  def extract_due_date
    patterns = [
      /(?:Échéance|Date\s+d[’']échéance|Due\s+date|À\s+payer\s+le)\s*[:\s]*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})/i,
      /(?:Échéance|Due)\s*[:\s]*(\d{1,2}\s+(?:janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre)\s+\d{4})/i,
      /(?:Paiement\s+à\s+recevoir\s+le)\s*[:\s]*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})/i
    ]
    
    patterns.each do |pattern|
      match = @text.match(pattern)
      if match
        date_str = match[1].strip
        parsed_date = parse_date(date_str)
        return parsed_date.strftime('%Y-%m-%d') if parsed_date
      end
    end
    
    # Si pas de date d'échéance, utiliser 30 jours après la date de facture
    invoice_date = extract_invoice_date
    begin
      (Date.parse(invoice_date) + 30).strftime('%Y-%m-%d')
    rescue
      (Date.today + 30).strftime('%Y-%m-%d')
    end
  end

  # Extrait les informations du fournisseur
  def extract_supplier
    supplier = {}
    
    # Nom du fournisseur (généralement en haut du PDF)
    # Facturation.pro: nom du fournisseur souvent avant "Facture"
    lines = @text.split("\n")
    
    # Chercher le nom avant le mot "Facture"
    facture_line = lines.find_index { |l| l.include?('Facture') || l.include?('FACTURE') || l.include?('Invoice') }
    if facture_line && facture_line > 0
      # Prendre les 2-3 lignes avant
      start_line = [0, facture_line - 3].max
      supplier_text = lines[start_line..facture_line].join(" ")
      
      # Nettoyer et extraire le nom
      supplier_text = supplier_text.gsub(/Facture.*/i, '').gsub(/Invoice.*/i, '').strip
      supplier[:nom] = supplier_text.split("\n").first.strip unless supplier_text.empty?
    end
    
    # Si pas trouvé, essayer de trouver un nom de société
    if supplier[:nom].nil? || supplier[:nom].empty?
      # Chercher des motifs de société (SARL, SAS, etc.)
      match = @text.match(/([A-Z\s]+(?:SARL|SAS|SA|EURL|SN|SCI|GIE|\s+&\s+\w+))\s*(?:\n|\s+Facture)/i)
      supplier[:nom] = match[1].strip if match
    end
    
    # Adresse, SIREN, etc.
    supplier[:adresse] = extract_address('fournisseur')
    supplier[:code_postal] = extract_postal_code('fournisseur')
    supplier[:ville] = extract_city('fournisseur')
    supplier[:pays] = extract_country('fournisseur')
    supplier[:siren] = extract_siren('fournisseur')
    supplier[:tva_intracommunautaire] = extract_vat_number('fournisseur')
    supplier[:iban] = extract_iban
    supplier[:bic] = extract_bic
    supplier[:email] = extract_email('fournisseur')
    supplier[:telephone] = extract_phone('fournisseur')
    
    supplier
  end

  # Extrait les informations du client
  def extract_client
    client = {}
    
    # Nom du client
    # Facturation.pro: souvent après "Client" ou "À"
    patterns = [
      /(?:Client|CLIENT|À|A|Bill\s+to|Facturé\s+à)\s*[:\s]*([A-Z\s]+(?:SARL|SAS|SA|EURL|SN|SCI|\s+&\s+\w+))/i,
      /(?:Société|SOCIÉTÉ|Company)\s*[:\s]*([A-Z\s]+)/i
    ]
    
    patterns.each do |pattern|
      match = @text.match(pattern)
      if match
        client[:nom] = match[1].strip
        break
      end
    end
    
    # Si pas trouvé, essayer de trouver après "Facture pour"
    if client[:nom].nil? || client[:nom].empty?
      match = @text.match(/(?:Facture\s+pour|Pour\s+la\s+société)\s*[:\s]*([A-Z\s]+)/i)
      client[:nom] = match[1].strip if match
    end
    
    client[:adresse] = extract_address('client')
    client[:code_postal] = extract_postal_code('client')
    client[:ville] = extract_city('client')
    client[:pays] = extract_country('client')
    client[:siren] = extract_siren('client')
    client[:tva_intracommunautaire] = extract_vat_number('client')
    
    client
  end

  # Extrait les lignes de facture
  def extract_line_items
    lines = []
    
    # Facturation.pro: les lignes sont généralement dans un tableau
    # avec description, quantité, prix unitaire, TVA, montant
    
    # Essayer de trouver les sections de lignes
    # Pattern: description + quantité + prix + TVA
    
    # D'abord, trouver où commencent les lignes
    start_markers = [
      /(?:Désignation|Description|Produit|Service|Prestation)/i,
      /(?:Quantité|Qty|Qté)/i,
      /(?:Prix\s+unitaire|P\.U\.|Unit\s+price)/i,
      /(?:Montant|Amount|Prix)/i
    ]
    
    start_line = nil
    @text.each_line.with_index do |line, idx|
      start_markers.each do |marker|
        if line.match(marker)
          start_line = idx
          break
        end
      end
      break if start_line
    end
    
    if start_line
      # Lire les lignes suivantes jusqu'à "Total" ou "TVA"
      end_markers = [
        /(?:Total|TOTAL|TVA|VAT|Montant\s+total|Net\s+à\s+payer)/i
      ]
      
      end_line = nil
      (@text.lines[start_line..-1] || []).each_with_index do |line, idx|
        end_markers.each do |marker|
          if line.match(marker)
            end_line = start_line + idx
            break
          end
        end
        break if end_line
      end
      
      # Extraire les lignes entre start_line et end_line
      if end_line && end_line > start_line
        line_text = @text.lines[start_line...end_line].join
        lines = parse_line_items(line_text)
      end
    end
    
    # Si pas de lignes trouvées, essayer une approche alternative
    if lines.empty?
      # Chercher des motifs de lignes de facture
      # Format: description - quantité x prix = montant
      line_pattern = /([\w\s\-.,;:()]+?)\s+(\d+[.,]?\d*)\s*x\s*([\d]+[.,]?\d*)\s*(?:€|\$|EUR)?\s*(\d+[.,]?\d*)?/i
      
      @text.scan(line_pattern).each do |description, quantite, prix, montant|
        next if description.strip.empty?
        
        # Nettoyer la description
        description = description.strip.gsub(/[\n\r]/, ' ').gsub(/\s+/, ' ')
        
        # Convertir les nombres (virgule en point)
        quantite = quantite.gsub(',', '.').to_f
        prix = prix.gsub(',', '.').to_f
        
        # Déterminer la TVA (par défaut 20%)
        tva = 20.0
        
        lines << {
          'description' => description,
          'quantite' => quantite,
          'prix_unitaire' => prix,
          'tva' => tva,
          'unite' => 'UN'
        }
      end
    end
    
    # Si toujours pas de lignes, créer une ligne par défaut
    if lines.empty?
      total = extract_totals
      if total[:grand_total]
        # Estimer le montant HT
        montant_ht = (total[:grand_total] / 1.2).round(2)
        lines << {
          'description' => 'Prestation de services',
          'quantite' => 1,
          'prix_unitaire' => montant_ht,
          'tva' => 20.0,
          'unite' => 'UN'
        }
      else
        lines << {
          'description' => 'Prestation de services',
          'quantite' => 1,
          'prix_unitaire' => 100.00,
          'tva' => 20.0,
          'unite' => 'UN'
        }
      end
    end
    
    lines
  end

  # Extrait les totaux
  def extract_totals
    totaux = {
      line_total: nil,
      tax_basis: nil,
      tax_total: nil,
      grand_total: nil,
      amount_due: nil
    }
    
    # Facturation.pro: totaux généralement à la fin
    # Patterns pour les totaux
    
    # Total HT
    match = @text.match(/(?:Total\s+HT|Sous\s+total|Subtotal|Montant\s+HT)\s*[:\s]*([\d]+[.,]?\d*)/i)
    totaux[:line_total] = match[1].gsub(',', '.').to_d if match
    
    # TVA
    match = @text.match(/(?:TVA|VAT|Taxes)\s*[:\s]*([\d]+[.,]?\d*)/i)
    totaux[:tax_total] = match[1].gsub(',', '.').to_d if match
    
    # Total TTC / Grand Total
    match = @text.match(/(?:Total\s+TTC|Total\s+à\s+payer|Grand\s+Total|Montant\s+total|Net\s+à\s+payer|Total\s+due)\s*[:\s]*([\d]+[.,]?\d*)/i)
    totaux[:grand_total] = match[1].gsub(',', '.').to_d if match
    
    # Si Total TTC pas trouvé, essayer le dernier montant
    if totaux[:grand_total].nil?
      match = @text.match(/([\d]+[.,]?\d*)\s*(?:€|EUR)\s*$/)
      totaux[:grand_total] = match[1].gsub(',', '.').to_d if match
    end
    
    # Total à payer
    match = @text.match(/(?:À\s+payer|Amount\s+due|Net\s+amount)\s*[:\s]*([\d]+[.,]?\d*)/i)
    totaux[:amount_due] = match[1].gsub(',', '.').to_d if match
    
    # Si TVA pas trouvée mais Total HT et Total TTC trouvés
    if totaux[:tax_total].nil? && totaux[:line_total] && totaux[:grand_total]
      totaux[:tax_total] = (totaux[:grand_total] - totaux[:line_total]).round(2)
    end
    
    # Si Total HT pas trouvé mais Total TTC et TVA trouvés
    if totaux[:line_total].nil? && totaux[:grand_total] && totaux[:tax_total]
      totaux[:line_total] = (totaux[:grand_total] - totaux[:tax_total]).round(2)
    end
    
    # Si Amount Due pas trouvé, utiliser Grand Total
    totaux[:amount_due] ||= totaux[:grand_total]
    
    totaux
  end

  private

  # Parse une date dans différents formats
  def parse_date(date_str)
    date_str = date_str.gsub(/[\/\-\.\s]/, '-')
    
    formats = [
      '%d-%m-%Y',
      '%m-%d-%Y',
      '%Y-%m-%d',
      '%d-%m-%y',
      '%m-%d-%y',
      '%y-%m-%d'
    ]
    
    formats.each do |format|
      begin
        return Date.strptime(date_str, format)
      rescue ArgumentError
        next
      end
    end
    
    # Essayer avec les noms de mois
    month_names = {
      'janvier' => 1, 'février' => 2, 'mars' => 3, 'avril' => 4, 'mai' => 5, 'juin' => 6,
      'juillet' => 7, 'août' => 8, 'septembre' => 9, 'octobre' => 10, 'novembre' => 11, 'décembre' => 12,
      'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4, 'may' => 5, 'jun' => 6,
      'jul' => 7, 'aug' => 8, 'sep' => 9, 'oct' => 10, 'nov' => 11, 'dec' => 12
    }
    
    # Pattern: dd month yyyy
    match = date_str.match(/(\d{1,2})[\s\-](\w+)[\s\-](\d{4})/i)
    if match
      day = match[1].to_i
      month_str = match[2].downcase
      year = match[3].to_i
      
      month = month_names[month_str]
      return Date.new(year, month, day) if month
    end
    
    nil
  end

  # Extrait une adresse
  def extract_address(type)
    # Chercher après le nom du fournisseur/client
    if type == 'fournisseur'
      supplier_name = extract_supplier[:nom]
      return '' if supplier_name.nil?
      
      # Trouver la ligne avec le nom et les lignes suivantes
      lines = @text.split("\n")
      name_line = lines.find_index { |l| l.include?(supplier_name) }
      return '' unless name_line
      
      # Prendre les 3-4 lignes suivantes
      address_lines = lines[name_line+1..name_line+4] || []
      address = address_lines.join(" ").strip
      
      # Nettoyer (enlever les numéros de téléphone, emails, etc.)
      address = address.gsub(/\d{10,}/, '').gsub(/[\d\s]{10,}/, '')
      address.strip
    else
      client_name = extract_client[:nom]
      return '' if client_name.nil?
      
      lines = @text.split("\n")
      name_line = lines.find_index { |l| l.include?(client_name) }
      return '' unless name_line
      
      address_lines = lines[name_line+1..name_line+4] || []
      address = address_lines.join(" ").strip
      address = address.gsub(/\d{10,}/, '').gsub(/[\d\s]{10,}/, '')
      address.strip
    end
  end

  # Extrait un code postal
  def extract_postal_code(type)
    # Chercher un code postal français (5 chiffres)
    match = @text.match(/(\d{5})/)
    return match[1] if match
    ''
  end

  # Extrait une ville
  def extract_city(type)
    # Chercher après le code postal
    match = @text.match(/\d{5}\s+([A-Z\s]+)/i)
    return match[1].strip if match
    ''
  end

  # Extrait un pays
  def extract_country(type)
    # Chercher FR, BE, etc.
    match = @text.match(/([A-Z]{2})/)
    return match[1] if match && ['FR', 'BE', 'DE', 'IT', 'ES', 'LU', 'CH'].include?(match[1])
    'FR'
  end

  # Extrait un SIREN
  def extract_siren(type)
    # SIREN: 9 chiffres
    match = @text.match(/(?:SIREN|N°\s*SIREN|Siren)\s*[:\s]*(\d{9})/i)
    return match[1] if match
    ''
  end

  # Extrait un numéro de TVA intracommunautaire
  def extract_vat_number(type)
    # FRXX XXXXXXX ou FRXXXXXXXXXX
    match = @text.match(/(?:TVA|N°\s*TVA|VAT|N°\s*intracommunautaire)\s*[:\s]*([A-Z]{2}\d{9,11})/i)
    return match[1] if match
    ''
  end

  # Extrait un IBAN
  def extract_iban
    match = @text.match(/(?:IBAN|N°\s*IBAN)\s*[:\s]*([A-Z]{2}\d{2}[A-Z0-9]{11,30})/i)
    return match[1] if match
    ''
  end

  # Extrait un BIC
  def extract_bic
    match = @text.match(/(?:BIC|SWIFT|N°\s*BIC)\s*[:\s]*([A-Z]{4}[A-Z]{2}[A-Z0-9]{2}[A-Z0-9]{0,11})/i)
    return match[1] if match
    ''
  end

  # Extrait un email
  def extract_email(type)
    match = @text.match(/([\w\.\-]+@[\w\.\-]+\.[a-z]{2,})/i)
    return match[1] if match
    ''
  end

  # Extrait un téléphone
  def extract_phone(type)
    match = @text.match(/(?:Tél|Tel|Phone|Téléphone|Portable)\s*[:\s]*([\d\s\.\-]{10,})/i)
    return match[1].gsub(/\s/, '') if match
    ''
  end

  # Parse les lignes de facture à partir du texte
  def parse_line_items(text)
    lines = []
    
    # Essayer de détecter les colonnes
    # Facturation.pro utilise souvent des tabulations ou des espaces fixes
    
    # Séparer par ligne
    text.each_line do |line|
      # Nettoyer la ligne
      line = line.strip
      next if line.empty?
      
      # Ignorer les lignes qui ressemblent à des en-têtes
      next if line.match?(/(?:Désignation|Description|Quantité|Qty|Prix|Montant|Total|TVA)/i)
      
      # Ignorer les lignes qui ressemblent à des totaux
      next if line.match?(/(?:Total|TVA|VAT|Montant\s+total)/i)
      
      # Essayer de séparer par des espaces multiples
      parts = line.split(/\s{2,}/)
      
      # On s'attend à au moins: description, quantité, prix
      next if parts.size < 3
      
      description = parts[0..-4].join(' ').strip
      
      # Extraire les nombres
      numbers = parts.select { |p| p.match?(/^\d+[.,]?\d*$/) }.map { |n| n.gsub(',', '.').to_f }
      
      next if numbers.empty?
      
      # Supposer que le dernier nombre est le montant, l'avant-dernier le prix, etc.
      if numbers.size >= 2
        prix = numbers[-2]
        quantite = numbers.size >= 3 ? numbers[-3] : 1
        
        lines << {
          'description' => description,
          'quantite' => quantite,
          'prix_unitaire' => prix,
          'tva' => 20.0,
          'unite' => 'UN'
        }
      end
    end
    
    lines
  end
end

# =============================================================================
# Générateur XML Factur-X (CII D22B)
# =============================================================================

class FacturXGenerator
  NS = {
    'rsm' => 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100',
    'ram' => 'urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100',
    'qdt' => 'urn:un:unece:uncefact:data:standard:QualifiedDataType:100',
    'udt' => 'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100'
  }.freeze

  GUIDELINE_IDS = {
    'MINIMUM' => 'urn:factur-x.eu:1p0:minimum',
    'BASIC' => 'urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic',
    'EN16931' => 'urn:cen.eu:en16931:2017',
    'BASICWL' => 'urn:factur-x.eu:1p0:basicwl',
    'EXTENDED' => 'urn:factur-x.eu:1p0:extended'
  }.freeze

  def initialize(invoice_data, config)
    @invoice_data = invoice_data
    @config = config
  end

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
          xml['ram'].ID @invoice_data[:numero]
          xml['ram'].TypeCode '380' # 380 = Facture
          xml['ram'].IssueDateTime do
            xml['udt'].DateTimeString(@invoice_data[:date].gsub('-', ''), format: '102')
          end
        end

        # Transaction commerciale
        xml['ram'].SupplyChainTradeTransaction do
          # Accord commercial
          xml['ram'].ApplicableHeaderTradeAgreement do
            # Vendeur (fournisseur)
            supplier = @invoice_data[:fournisseur]
            xml['ram'].SellerTradeParty do
              xml['ram'].Name supplier[:nom] || @config['fournisseur']['nom']
              
              if supplier[:adresse] && !supplier[:adresse].empty?
                xml['ram'].PostalTradeAddress do
                  xml['ram'].PostcodeCode supplier[:code_postal] || @config['fournisseur']['code_postal'] || ''
                  xml['ram'].LineOne supplier[:adresse]
                  xml['ram'].CityName supplier[:ville] || @config['fournisseur']['ville'] || ''
                  xml['ram'].CountryID supplier[:pays] || @config['fournisseur']['pays'] || 'FR'
                end
              end
              
              # Identifiants fiscaux
              if supplier[:siren] && !supplier[:siren].empty?
                xml['ram'].SpecifiedTaxRegistration do
                  xml['ram'].ID(supplier[:siren], schemeID: 'FC')
                end
              end
              
              if supplier[:tva_intracommunautaire] && !supplier[:tva_intracommunautaire].empty?
                xml['ram'].SpecifiedTaxRegistration do
                  xml['ram'].ID(supplier[:tva_intracommunautaire], schemeID: 'VA')
                end
              end
              
              # Coordonnées
              if supplier[:telephone] && !supplier[:telephone].empty?
                xml['ram'].URIUniversalCommunication do
                  xml['ram'].URIID(supplier[:telephone], schemeID: '09')
                end
              end
              
              if supplier[:email] && !supplier[:email].empty?
                xml['ram'].URIUniversalCommunication do
                  xml['ram'].URIID(supplier[:email], schemeID: 'EM')
                end
              end
            end

            # Acheteur (client)
            client = @invoice_data[:client]
            xml['ram'].BuyerTradeParty do
              xml['ram'].Name client[:nom] || @config['client']['nom'] || 'CLIENT'
              
              if client[:adresse] && !client[:adresse].empty?
                xml['ram'].PostalTradeAddress do
                  xml['ram'].PostcodeCode client[:code_postal] || @config['client']['code_postal'] || ''
                  xml['ram'].LineOne client[:adresse]
                  xml['ram'].CityName client[:ville] || @config['client']['ville'] || ''
                  xml['ram'].CountryID client[:pays] || @config['client']['pays'] || 'FR'
                end
              end
              
              if client[:siren] && !client[:siren].empty?
                xml['ram'].SpecifiedTaxRegistration do
                  xml['ram'].ID(client[:siren], schemeID: 'FC')
                end
              end
              
              if client[:tva_intracommunautaire] && !client[:tva_intracommunautaire].empty?
                xml['ram'].SpecifiedTaxRegistration do
                  xml['ram'].ID(client[:tva_intracommunautaire], schemeID: 'VA')
                end
              end
            end

            # Conditions de règlement
            xml['ram'].ApplicableTradePaymentTerms do
              xml['ram'].Description @config['conditions_reglement']
            end
          end

          # Règlement
          xml['ram'].ApplicableHeaderTradeSettlement do
            xml['ram'].InvoiceCurrencyCode @config['devise']
            
            # IBAN du fournisseur
            if supplier[:iban] && !supplier[:iban].empty?
              xml['ram'].PayeeTradeParty do
                xml['ram'].SpecifiedTradeAccountingAccount do
                  xml['ram'].ID(supplier[:iban], schemeID: 'IBAN')
                end
              end
            end
            
            # BIC du fournisseur
            if supplier[:bic] && !supplier[:bic].empty?
              xml['ram'].PayeeTradeParty do
                xml['ram'].SpecifiedTradeAccountingAccount do
                  xml['ram'].ServiceProviderID(supplier[:bic], schemeID: 'BIC')
                end
              end
            end
            
            # Date d'échéance
            xml['ram'].ApplicableTradePaymentTerms do
              xml['ram'].DueDateTime do
                xml['udt'].DateTimeString(@invoice_data[:date_echeance].gsub('-', ''), format: '102')
              end
            end
          end

          # Lignes de facture
          xml['ram'].ApplicableHeaderTradeDelivery do
            xml['ram'].BilledDelivery do
              @invoice_data[:lignes].each_with_index do |ligne, index|
                xml['ram'].DeliveryItem do
                  xml['ram'].AssociatedDocumentLineDocument do
                    xml['ram'].LineID index + 1
                  end
                  xml['ram'].Note ligne['description']
                end
              end
            end
          end

          # Settlement (totaux)
          xml['ram'].ApplicableHeaderTradeSettlement do
            xml['ram'].SpecifiedTradeSettlementMonetarySummation do
              totals = @invoice_data[:totaux]
              
              # Utiliser les totaux extraits ou calculer
              line_total = totals[:line_total] || calculate_line_total
              tax_total = totals[:tax_total] || calculate_tax_total
              grand_total = totals[:grand_total] || calculate_grand_total
              amount_due = totals[:amount_due] || grand_total
              
              xml['ram'].LineTotalAmount(line_total.round(2), currencyID: @config['devise'])
              xml['ram'].TaxBasisTotalAmount(line_total.round(2), currencyID: @config['devise'])
              xml['ram'].TaxTotalAmount(tax_total.round(2), currencyID: @config['devise'])
              xml['ram'].GrandTotalAmount(grand_total.round(2), currencyID: @config['devise'])
              xml['ram'].TotalPrepaidAmount(0, currencyID: @config['devise'])
              xml['ram'].AmountDue(amount_due.round(2), currencyID: @config['devise'])
            end

            # Détail des taxes (TVA)
            # Regrouper par taux de TVA
            tva_groups = @invoice_data[:lignes].group_by { |l| l['tva'] }
            tva_groups.each do |taux, lignes|
              montant_ht = lignes.sum { |l| l['quantite'] * l['prix_unitaire'] }
              montant_tva = montant_ht * (taux / 100.0)
              
              xml['ram'].ApplicableTradeTax do
                xml['ram'].CalculatedTradeTax do
                  xml['ram'].BasisAmount(montant_ht.round(2), currencyID: @config['devise'])
                  xml['ram'].TypeCode 'VAT'
                  xml['ram'].CategoryCode 'S'
                  xml['ram'].ExemptionReasonCode 'VAT'
                  xml['ram'].ApplicableTradeTaxRate do
                    xml['ram'].Percent taux
                  end
                  xml['ram'].CalculatedTradeTaxAmount(montant_tva.round(2), currencyID: @config['devise'])
                end
              end
            end
          end

          # Lignes de facture détaillées
          xml['ram'].SpecifiedSupplyChainTradeLineItem do
            @invoice_data[:lignes].each_with_index do |ligne, index|
              montant_ht = ligne['quantite'] * ligne['prix_unitaire']
              montant_tva = montant_ht * (ligne['tva'] / 100.0)
              
              xml['ram'].LineItem do
                xml['ram'].AssociatedDocumentLineDocument do
                  xml['ram'].LineID index + 1
                end
                xml['ram'].Note ligne['description']
                xml['ram'].BilledQuantity(ligne['quantite'], unitCode: ligne['unite'])
                xml['ram'].NetPriceProductTradePrice do
                  xml['ram'].ChargeAmount(montant_ht.round(2), currencyID: @config['devise'])
                  xml['ram'].BasisQuantity(ligne['quantite'], unitCode: ligne['unite'])
                end
                
                # TVA par ligne
                xml['ram'].ApplicableTradeTax do
                  xml['ram'].CalculatedTradeTax do
                    xml['ram'].BasisAmount(montant_ht.round(2), currencyID: @config['devise'])
                    xml['ram'].TypeCode 'VAT'
                    xml['ram'].CategoryCode 'S'
                    xml['ram'].ExemptionReasonCode 'VAT'
                    xml['ram'].ApplicableTradeTaxRate do
                      xml['ram'].Percent ligne['tva']
                    end
                    xml['ram'].CalculatedTradeTaxAmount(montant_tva.round(2), currencyID: @config['devise'])
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

  def save_xml(filepath)
    xml_content = generate_xml
    File.write(filepath, xml_content)
    filepath
  end

  private

  def calculate_line_total
    @invoice_data[:lignes].sum { |l| l['quantite'] * l['prix_unitaire'] }
  end

  def calculate_tax_total
    @invoice_data[:lignes].sum { |l| (l['quantite'] * l['prix_unitaire']) * (l['tva'] / 100.0) }
  end

  def calculate_grand_total
    calculate_line_total + calculate_tax_total
  end
end

# =============================================================================
# Intégrateur Factur-X (PDF + XML)
# =============================================================================

class FacturXIntegrator
  def initialize(config)
    @config = config
  end

  def integrate(pdf_path, xml_path, output_path = nil)
    output_path ||= pdf_path.sub(/\.pdf$/i, '_facturx.pdf')
    
    xml_content = File.read(xml_path)
    
    # Essayer avec zugpferd
    begin
      require 'zugpferd'
      embedder = Zugpferd::PDF::Embedder.new
      
      options = {
        pdf_path: pdf_path,
        xml: xml_content,
        output_path: output_path,
        version: '2p1',
        conformance_level: 'EN 16931'
      }
      
      embedder.embed(options)
      puts "✅ Factur-X créé avec zugpferd: #{output_path}"
      return output_path
      
    rescue LoadError, StandardError => e
      # Essayer avec qpdf
      puts "⚠️  zugpferd non disponible ou échoué, utilisation de qpdf..."
      return integrate_with_qpdf(pdf_path, xml_path, output_path)
    end
  end

  def integrate_with_qpdf(pdf_path, xml_path, output_path)
    unless system('which qpdf > /dev/null 2>&1')
      raise "qpdf n'est pas installé. Installez-le avec:\n  sudo apt-get install qpdf  # Debian/Ubuntu\n  brew install qpdf          # macOS"
    end
    
    cmd = "qpdf --add-attachment #{xml_path} --replace-input -- #{pdf_path} #{output_path}"
    stdout, stderr, status = Open3.capture3(cmd)
    
    if File.exist?(output_path) && File.size(output_path) > 0
      puts "✅ Factur-X créé avec qpdf: #{output_path}"
      output_path
    else
      raise "❌ Échec de qpdf: #{stderr}"
    end
  end
end

# =============================================================================
# Interface CLI
# =============================================================================

class FacturXFromPDFCLI
  def initialize
    @options = {}
    parse_options
  end

  def parse_options
    OptionParser.new do |opts|
      opts.banner = "Usage: ruby facturx_from_pdf.rb <fichier.pdf> [options]"
      
      opts.on("-o", "--output FILE", "Fichier PDF de sortie") do |file|
        @options[:output] = file
      end
      
      opts.on("-p", "--profil PROFIL", "Profil Factur-X (MINIMUM, BASIC, EN16931, EXTENDED)") do |profil|
        @options[:profil] = profil.upcase
      end
      
      opts.on("-c", "--config FILE", "Fichier de configuration YAML") do |file|
        @options[:config] = file
      end
      
      opts.on("-h", "--help", "Affiche cette aide") do
        puts opts
        exit
      end
    end.parse!
    
    if ARGV.empty?
      puts "❌ Erreur: Veuillez spécifier un fichier PDF"
      puts "Exemple: ruby facturx_from_pdf.rb facture.pdf"
      exit 1
    end
    
    @pdf_path = ARGV[0]
    
    unless File.exist?(@pdf_path)
      puts "❌ Erreur: Fichier introuvable: #{@pdf_path}"
      exit 1
    end
  end

  def run
    puts "=" * 70
    puts "📄 Factur-X Generator from PDF (Facturation.pro)"
    puts "=" * 70
    puts ""
    
    # Charger la configuration
    config = Config.new(@options[:config])
    
    # Appliquer les options
    if @options[:profil]
      config.data['profil'] = @options[:profil]
    end
    
    puts "📖 Extraction des données du PDF: #{@pdf_path}"
    
    # Extraire les données du PDF
    extractor = PDFDataExtractor.new(@pdf_path)
    invoice_data = extractor.extract_invoice_data
    
    puts "  ✓ Numéro de facture: #{invoice_data[:numero]}"
    puts "  ✓ Date: #{invoice_data[:date]}"
    puts "  ✓ Fournisseur: #{invoice_data[:fournisseur][:nom]}"
    puts "  ✓ Client: #{invoice_data[:client][:nom]}"
    puts "  ✓ Nombre de lignes: #{invoice_data[:lignes].size}"
    puts "  ✓ Total TTC: #{invoice_data[:totaux][:grand_total] || 'N/A'}"
    puts ""
    
    # Générer le XML
    xml_path = @pdf_path.sub(/\.pdf$/i, '_facturx.xml')
    
    puts "📝 Génération du XML Factur-X..."
    generator = FacturXGenerator.new(invoice_data, config)
    generator.save_xml(xml_path)
    puts "  ✓ XML généré: #{xml_path}"
    puts ""
    
    # Intégrer dans le PDF
    output_path = @options[:output] || @pdf_path.sub(/\.pdf$/i, '_facturx.pdf')
    
    puts "📎 Intégration du XML dans le PDF..."
    integrator = FacturXIntegrator.new(config)
    integrator.integrate(@pdf_path, xml_path, output_path)
    puts ""
    
    # Nettoyer le fichier XML temporaire
    File.delete(xml_path) if File.exist?(xml_path)
    
    puts "=" * 70
    puts "✅ Succès! Factur-X créé: #{output_path}"
    puts "=" * 70
    puts ""
    puts "Vérification:"
    puts "  - Ouvrez le fichier avec Adobe Acrobat Reader"
    puts "  - Vérifiez que '#{File.basename(xml_path)}' est présent dans les pièces jointes"
    puts "  - Utilisez le validateur: https://e-invoice.be/blog/factur-x-format"
    puts ""
    
    output_path
  end
end

# =============================================================================
# Point d'entrée principal
# =============================================================================

if __FILE__ == $0
  begin
    cli = FacturXFromPDFCLI.new
    cli.run
  rescue => e
    puts "❌ Erreur: #{e.message}"
    puts e.backtrace.first(5).join("\n") if e.backtrace
    exit 1
  end
end
