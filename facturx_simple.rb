#!/usr/bin/env ruby
# encoding: UTF-8

# =============================================================================
# Script Ruby SIMPLE pour Factur-X
# 
# Ce script minimaliste permet de créer rapidement une facture Factur-X
# à partir d'un PDF existant en générant un XML basique.
# 
# Utilisation:
#   ruby facturx_simple.rb facture.pdf "NOM_CLIENT" "MONTANT_TTC"
# 
# Exemple:
#   ruby facturx_simple.rb ma_facture.pdf "Société XYZ" "1200.00"
# 
# Dépendances: zugpferd, nokogiri
# Installation: gem install zugpferd nokogiri
# 
# =============================================================================

require 'zugpferd'
require 'nokogiri'
require 'date'

# Vérifier les arguments
if ARGV.size < 3
  puts "Usage: ruby facturx_simple.rb <pdf> <nom_client> <montant_ttc> [num_facture]"
  puts ""
  puts "Exemple: ruby facturx_simple.rb facture.pdf \"Société XYZ\" 1200.00 FACT-001"
  exit 1
end

pdf_path = ARGV[0]
client_name = ARGV[1]
montant_ttc = ARGV[2].to_f
facture_num = ARGV[3] || "FACT-#{Date.today.strftime('%Y%m%d')}-001"

# Vérifier que le PDF existe
unless File.exist?(pdf_path)
  puts "❌ Erreur: Fichier PDF introuvable: #{pdf_path}"
  exit 1
end

# Générer le XML Factur-X minimal
xml_content = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <rsm:CrossIndustryInvoice
    xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
    xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
    xmlns:qdt="urn:un:unece:uncefact:data:standard:QualifiedDataType:100"
    xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100 CrossIndustryInvoice_100pD22B.xsd"
    GuidelineID="urn:cen.eu:en16931:2017">
    
    <ram:ExchangedDocument>
      <ram:ID>#{facture_num}</ram:ID>
      <ram:TypeCode>380</ram:TypeCode>
      <ram:IssueDateTime>
        <udt:DateTimeString format="102">#{Date.today.strftime('%Y%m%d')}</udt:DateTimeString>
      </ram:IssueDateTime>
    </ram:ExchangedDocument>
    
    <ram:SupplyChainTradeTransaction>
      <ram:ApplicableHeaderTradeAgreement>
        <ram:SellerTradeParty>
          <ram:Name>MA SOCIETE</ram:Name>
          <ram:PostalTradeAddress>
            <ram:PostcodeCode>75001</ram:PostcodeCode>
            <ram:LineOne>123 Rue de la Facture</ram:LineOne>
            <ram:CityName>PARIS</ram:CityName>
            <ram:CountryID>FR</ram:CountryID>
          </ram:PostalTradeAddress>
          <ram:SpecifiedTaxRegistration>
            <ram:ID schemeID="FC">123456789</ram:ID>
          </ram:SpecifiedTaxRegistration>
          <ram:SpecifiedTaxRegistration>
            <ram:ID schemeID="VA">FR123456789</ram:ID>
          </ram:SpecifiedTaxRegistration>
        </ram:SellerTradeParty>
        
        <ram:BuyerTradeParty>
          <ram:Name>#{client_name}</ram:Name>
          <ram:PostalTradeAddress>
            <ram:PostcodeCode>75002</ram:PostcodeCode>
            <ram:LineOne>Adresse Client</ram:LineOne>
            <ram:CityName>PARIS</ram:CityName>
            <ram:CountryID>FR</ram:CountryID>
          </ram:PostalTradeAddress>
        </ram:BuyerTradeParty>
        
        <ram:ApplicableTradePaymentTerms>
          <ram:Description>30 jours net</ram:Description>
        </ram:ApplicableTradePaymentTerms>
      </ram:ApplicableHeaderTradeAgreement>
      
      <ram:ApplicableHeaderTradeSettlement>
        <ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>
        <ram:PayeeTradeParty>
          <ram:SpecifiedTradeAccountingAccount>
            <ram:ID schemeID="IBAN">FR7612345678901234567890123</ram:ID>
          </ram:SpecifiedTradeAccountingAccount>
        </ram:PayeeTradeParty>
        
        <ram:ApplicableTradePaymentTerms>
          <ram:DueDateTime>
            <udt:DateTimeString format="102">#{(Date.today + 30).strftime('%Y%m%d')}</udt:DateTimeString>
          </ram:DueDateTime>
        </ram:ApplicableTradePaymentTerms>
        
        <ram:SpecifiedTradeSettlementMonetarySummation>
          <ram:LineTotalAmount currencyID="EUR">#{(montant_ttc / 1.2).round(2)}</ram:LineTotalAmount>
          <ram:TaxBasisTotalAmount currencyID="EUR">#{(montant_ttc / 1.2).round(2)}</ram:TaxBasisTotalAmount>
          <ram:TaxTotalAmount currencyID="EUR">#{(montant_ttc - (montant_ttc / 1.2)).round(2)}</ram:TaxTotalAmount>
          <ram:GrandTotalAmount currencyID="EUR">#{montant_ttc.round(2)}</ram:GrandTotalAmount>
          <ram:TotalPrepaidAmount currencyID="EUR">0.00</ram:TotalPrepaidAmount>
          <ram:AmountDue currencyID="EUR">#{montant_ttc.round(2)}</ram:AmountDue>
        </ram:SpecifiedTradeSettlementMonetarySummation>
        
        <ram:ApplicableTradeTax>
          <ram:CalculatedTradeTax>
            <ram:BasisAmount currencyID="EUR">#{(montant_ttc / 1.2).round(2)}</ram:BasisAmount>
            <ram:TypeCode>VAT</ram:TypeCode>
            <ram:CategoryCode>S</ram:CategoryCode>
            <ram:ExemptionReasonCode>VAT</ram:ExemptionReasonCode>
            <ram:ApplicableTradeTaxRate>
              <ram:Percent>20.0</ram:Percent>
            </ram:ApplicableTradeTaxRate>
            <ram:CalculatedTradeTaxAmount currencyID="EUR">#{(montant_ttc - (montant_ttc / 1.2)).round(2)}</ram:CalculatedTradeTaxAmount>
          </ram:CalculatedTradeTax>
        </ram:ApplicableTradeTax>
      </ram:ApplicableHeaderTradeSettlement>
      
      <ram:SpecifiedSupplyChainTradeLineItem>
        <ram:LineItem>
          <ram:AssociatedDocumentLineDocument>
            <ram:LineID>1</ram:LineID>
          </ram:AssociatedDocumentLineDocument>
          <ram:Note>Prestation de services</ram:Note>
          <ram:BilledQuantity unitCode="UN">1</ram:BilledQuantity>
          <ram:NetPriceProductTradePrice>
            <ram:ChargeAmount currencyID="EUR">#{(montant_ttc / 1.2).round(2)}</ram:ChargeAmount>
            <ram:BasisQuantity unitCode="UN">1</ram:BasisQuantity>
          </ram:NetPriceProductTradePrice>
          <ram:ApplicableTradeTax>
            <ram:CalculatedTradeTax>
              <ram:BasisAmount currencyID="EUR">#{(montant_ttc / 1.2).round(2)}</ram:BasisAmount>
              <ram:TypeCode>VAT</ram:TypeCode>
              <ram:CategoryCode>S</ram:CategoryCode>
              <ram:ExemptionReasonCode>VAT</ram:ExemptionReasonCode>
              <ram:ApplicableTradeTaxRate>
                <ram:Percent>20.0</ram:Percent>
              </ram:ApplicableTradeTaxRate>
              <ram:CalculatedTradeTaxAmount currencyID="EUR">#{(montant_ttc - (montant_ttc / 1.2)).round(2)}</ram:CalculatedTradeTaxAmount>
            </ram:CalculatedTradeTax>
          </ram:ApplicableTradeTax>
        </ram:LineItem>
      </ram:SpecifiedSupplyChainTradeLineItem>
    </ram:SupplyChainTradeTransaction>
  </rsm:CrossIndustryInvoice>
XML

# Sauvegarder le XML temporairement
xml_path = pdf_path.sub(/\.pdf$/i, '.xml')
File.write(xml_path, xml_content)

# Intégrer le XML dans le PDF
output_path = pdf_path.sub(/\.pdf$/i, '_facturx.pdf')

begin
  # Essayer avec zugpferd
  embedder = Zugpferd::PDF::Embedder.new
  embedder.embed(
    pdf_path: pdf_path,
    xml: xml_content,
    output_path: output_path,
    version: '2p1',
    conformance_level: 'EN 16931'
  )
  
  puts "✅ Factur-X créé avec zugpferd: #{output_path}"
  
rescue => e
  # Essayer avec qpdf
  puts "⚠️  zugpferd a échoué, tentative avec qpdf..."
  
  unless system('which qpdf > /dev/null 2>&1')
    puts "❌ qpdf n'est pas installé. Installez-le avec:"
    puts "  sudo apt-get install qpdf  # Debian/Ubuntu"
    puts "  brew install qpdf          # macOS"
    File.delete(xml_path) if File.exist?(xml_path)
    exit 1
  end
  
  success = system("qpdf --add-attachment #{xml_path} -- #{pdf_path} #{output_path}")
  
  if success
    puts "✅ Factur-X créé avec qpdf: #{output_path}"
  else
    puts "❌ Échec de la création du Factur-X"
    File.delete(xml_path) if File.exist?(xml_path)
    exit 1
  end
end

# Nettoyer
File.delete(xml_path) if File.exist?(xml_path)

puts ""
puts "Vérification:"
puts "  - Ouvrez #{output_path} avec Adobe Acrobat Reader"
puts "  - Vérifiez que 'factur-x.xml' est présent dans les pièces jointes"
puts "  - Utilisez le validateur: https://e-invoice.be/blog/factur-x-format"
