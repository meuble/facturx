# frozen_string_literal: true

require "spec_helper"

RSpec.describe FacturX::PdfExtractor do
  it "keeps column spacing separate from quantities and amounts" do
    extractor = described_class.allocate
    text = <<~TEXT
      Désignation                                      % TVA       PU HT     Qté     Total HT
      Example service
      Fictional maintenance work
      Developer                                          20.0 %     722,50 €    2    1 445,00 €
      Example support
      Fictional support work
      Developer                                          20.0 %     722,50 €    4    2 890,00 €
      Total HT    4 335,00 €
      TVA 20.0 %    867,00 €
      TOTAL TTC    5 202,00 €
      PPF: 123456789
      PEPPOL: 0225:123456789
      En cas de retard de paiement, indemnité forfaitaire légale pour frais de recouvrement : 40,00 €
      Taux des pénalités en cas de retard de paiement : taux directeur de refinancement de la BCE, majoré de 10 points
      Escompte en cas de paiement anticipé : aucun
    TEXT
    extractor.instance_variable_set(:@text, text)
    extractor.instance_variable_set(:@lines, text.split(/\n+/).map(&:strip).reject(&:empty?))

    data = extractor.to_invoice_data

    expect(data.line_items.map { |item| [item[:quantity], item[:line_total_amount]] }).to eq([
      [2, BigDecimal("1445")],
      [4, BigDecimal("2890")]
    ])
    expect(data.tax_breakdowns.first[:tax_amount]).to eq(BigDecimal("867"))
    expect(data.tax_inclusive_amount).to eq(BigDecimal("5202"))
    expect(data.seller[:electronic_address]).to eq("123456789")
    expect(data.seller[:electronic_address_scheme]).to eq("0225")
    expect(data.legal_notes["PMT"]).to start_with("En cas de retard de paiement")
    expect(data.validate).not_to include(/Line item|Grand total|Taxable amounts/)
  end
end
