# frozen_string_literal: true

require "spec_helper"

RSpec.describe FacturX::PdfExtractor do
  it "keeps column spacing separate from quantities and amounts" do
    extractor = described_class.allocate
    text = <<~TEXT
      Désignation                                      % TVA       PU HT     Qté     Total HT
      Wiziboat - App Update
      #72 - Update NodeJS version
      Développeur                                      20.0 %     722,50 €    2    1 445,00 €
      Wiziboat - Planet Service deployment
      #76 - Configure deployment on Planet service
      Développeur                                      20.0 %     722,50 €    4    2 890,00 €
      Total HT    4 335,00 €
      TVA 20.0 %    867,00 €
      TOTAL TTC    5 202,00 €
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
    expect(data.validate).not_to include(/Line item|Grand total|Taxable amounts/)
  end
end
