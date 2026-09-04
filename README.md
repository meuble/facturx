# FacturX

A lightweight Ruby library and CLI for generating **Factur-X / ZUGFeRD** conformant hybrid PDF invoices.

- **Language**: Ruby (3.1+)
- **Profiles supported**: `MINIMUM`, `BASICWL`, `BASIC`, `EN16931`, `EXTENDED`
- **PDF/A conformance**: PDF/A-3b with embedded CII XML
- **Spec**: EN 16931-1, Factur-X v1.0

---

## Installation

```bash
git clone <repo-url> facturx
cd facturx
bundle install
```

Requires:
- Ruby ≥ 3.1 (tested on 3.4.7)
- Bundler

---

## Quick Start — CLI

### Zero-config mode (recommended)

The tool automatically extracts invoice data from the PDF and generates a valid Factur-X PDF:

```bash
ruby -Ilib bin/facturx input.pdf -o output-facturx.pdf
```

That's it. The generated artifact is checked locally for the required Factur-X
attachment and PDF/A output intent. You should still run it through your PDP's
validator before sending it.

### Optional YAML override

If the PDF extraction misses something (or you want to override specific fields), create a partial YAML file:

```yaml
# override.yaml
seller:
  electronic_address: "team@foreverbije.com"
  electronic_address_scheme: "EM"
```

And pass it:

```bash
ruby -Ilib bin/facturx input.pdf -c override.yaml -o output-facturx.pdf
```

The YAML values override the auto-extracted ones. Only specify what you want to change.

### Extract and review

To see what the tool extracted from the PDF (as YAML):

```bash
ruby -Ilib bin/facturx input.pdf -e
```

This is useful for verifying extraction quality before generating.

### Interactive review mode

To review and confirm every extracted field before generating:

```bash
ruby -Ilib bin/facturx input.pdf -i -o output-facturx.pdf
```

The CLI will prompt you for every extracted field (seller, buyer, invoice, line items, VAT breakdowns, and totals), showing the extracted value as a default. Just press Enter to accept, or type a new value to override. Validation runs after the review. This is especially useful for:
- Verifying buyer email (BT-49) instead of using a placeholder
- Correcting buyer SIRET/SIREN classification for B2B/B2C
- Confirming TVA numbers and addresses

### Options

| Flag | Description |
|------|-------------|
| `-o, --output FILE` | Output PDF path (default: `<input>_facturx.pdf`) |
| `-c, --config FILE` | Optional YAML file to override extracted data |
| `-p, --profile PROFILE` | Factur-X profile: MINIMUM, BASICWL, BASIC, EN16931, EXTENDED |
| `-e, --extract` | Extract data as YAML, do not generate PDF |
| `-i, --interactive` | Review and confirm extracted data interactively before generating |
| `--validate` | Validate without generating |
| `-v, --version` | Show version |

---

## Library Usage

```ruby
require "facturx"

# 1. Auto-extract from PDF
data = FacturX::PdfExtractor.new("input.pdf").to_invoice_data

# 2. Or build manually
data = FacturX::InvoiceData.new(
  profile: "EN16931",
  number: "2026-001",
  issue_date: Date.new(2026, 1, 15),
  currency_code: "EUR",
  seller: { name: "Acme Corp", country_code: "FR", vat_identifier: "FR123456789" },
  buyer:  { name: "Client SA",  country_code: "FR" },
  line_items: [
    { id: "1", name: "Consulting", quantity: 1, unit_code: "C62",
      price_amount: 1000.00, line_total_amount: 1000.00,
      tax_percent: 20.0, tax_category: "S" }
  ],
  tax_breakdowns: [
    { taxable_amount: 1000.00, tax_amount: 200.00, tax_percent: 20.0, tax_category: "S" }
  ],
  line_extension_amount: 1000.00,
  tax_exclusive_amount:  1000.00,
  tax_inclusive_amount:  1200.00,
  payable_amount:        1200.00
)

# Validate
raise "Invalid invoice" unless data.valid?

# Generate Factur-X PDF
FacturX.generate(
  input_pdf: "input.pdf",
  output_pdf: "output-facturx.pdf",
  data: data
)
```

For XSD validation against the official CII schema, set
`FACTURX_CII_SCHEMA=/path/to/CrossIndustryInvoice_100pD16B.xsd` when running
the command. EN 16931 Schematron validation remains dependent on the official
rule distribution and should be run in the target PDP validator.

---

## What Gets Extracted Automatically

From a typical French B2B invoice PDF, the tool extracts:

| Field | Source |
|-------|--------|
| Invoice number | "FACTURE N° …" |
| Issue date | "Date : …" |
| Due date | "Date limite de règlement : …" |
| Note | "Objet : …" |
| Seller name | Block before "FACTURE" |
| Seller address | Street + postal code + city |
| Seller TVA | "N° TVA …" (first occurrence) |
| Seller SIREN | "SIREN …" or "… RCS" |
| Seller IBAN/BIC | "IBAN: …", "BIC: …" |
| Buyer name | Line before "FACTURE" |
| Buyer address | Street + postal code |
| Buyer TVA | "Client – N° TVA …" |
| Buyer SIRET | "SIRET: …" |
| Line items | Table rows (name, description, qty, price, total) |
| Totals | "Total HT", "TVA …", "TOTAL TTC" |
| Tax breakdown | Computed from totals and rate |

If any field is missing or wrong, use `-e` to inspect, then create a small YAML override.

---

## Architecture

```
lib/
├── facturx.rb              # Main entry point
└── facturx/
    ├── version.rb           # 2.0.0
    ├── invoice_data.rb      # Structured data model + validation
    ├── config.rb            # YAML loader with deep merge (optional override)
    ├── xml_generator.rb     # CII XML via zugpferd gem
    ├── pdf_embedder.rb      # PDF/A-3 embedding via hexapdf
    └── pdf_extractor.rb     # Auto-extraction from PDF text
```

### Key Design Decisions

1. **zugpferd** for XML generation — produces valid CII D16B XML, avoids hand-rolled XML pitfalls.
2. **hexapdf** for PDF manipulation — writes low-level structures (Names tree, AF array, XMP, OutputIntent) without shelling out.
3. **InvoiceData** validation — checks field presence, monetary consistency (line totals, tax, grand total), and required EN 16931 fields before generation.
4. **PDF/A metadata** — sets the associated-file relationship, embedded-file parameters, and an sRGB ICC output profile.
5. **Auto-extraction** — zero-config approach: parse the PDF text heuristically, then let the user optionally override with YAML.

---

## Validation

Upload the generated PDF to:
- [SuperPDP Factur-X Validator](https://www.superpdp.tech/outils/validateur-facture-electronique)

The tool verifies:
- CII XML syntax and schema
- Factur-X profile compliance
- PDF/A-3b structure (embedded file, XMP metadata, AF array)

---

## Testing

```bash
bundle exec rspec
```

Tests cover:
- `InvoiceData` validation (presence, totals coherence, profile IDs)
- `Config` YAML loading and deep merge
- `PdfExtractor` auto-extraction from sample PDF text
- `XmlGenerator` CII structure verification
- `PdfEmbedder` PDF/A-3 structure (Names, AF, Metadata, OutputIntents)
- End-to-end integration: PDF → extract → XML → PDF

---

## Resources

- [FNFE-MPE — Implementer Factur-X](https://fnfe-mpe.org/factur-x/implementer-factur-x/)
- [Factur-X Specifications (PDF)](https://fnfe-mpe.org/factur-x/)
- [EN 16931-1](https://www.cen.eu/) — European standard for e-invoicing
- [ZUGFeRD/Factur-X Technical Specification](https://www.ferd-net.de/)

---

## License

MIT
