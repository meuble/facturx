# frozen_string_literal: true

require "date"
require "bigdecimal"
require "bigdecimal/util"

module FacturX
  # Extracts structured invoice data from a PDF text layout.
  #
  # Tuned for common French B2B service invoices. Uses conservative
  # heuristics: uncertain fields are left blank rather than guessed.
  class PdfExtractor
    attr_reader :text, :lines

    def initialize(pdf_path)
      raise "File not found: #{pdf_path}" unless File.exist?(pdf_path)
      @text  = extract_text(pdf_path)
      @lines = @text.split(/\n+/).map(&:strip).reject(&:empty?)
    end

    def to_invoice_data(profile: "EN16931")
      seller = extract_seller
      buyer  = extract_buyer
      items  = extract_line_items
      totals = compute_totals(items)

      FacturX::InvoiceData.new(
        profile:               profile,
        number:                extract_invoice_number,
        issue_date:            extract_issue_date,
        due_date:              extract_due_date,
        currency_code:         "EUR",
        note:                  extract_note,
        seller:                seller,
        buyer:                 buyer,
        line_items:            items,
        tax_breakdowns:        build_tax_breakdown(totals),
        line_extension_amount: totals[:line_extension],
        tax_exclusive_amount:  totals[:tax_exclusive],
        tax_inclusive_amount:  totals[:tax_inclusive],
        payable_amount:        totals[:payable],
        prepaid_amount:        0
      )
    end

    private

    def extract_text(pdf_path)
      begin
        require "pdf-reader"
        reader = PDF::Reader.new(pdf_path)
        return reader.pages.map(&:text).join("\n")
      rescue LoadError
        txt = Tempfile.new(["facturx", ".txt"])
        system("pdftotext", "-layout", pdf_path, txt.path, out: "/dev/null", err: "/dev/null")
        return File.read(txt.path)
      rescue => e
        raise "Cannot extract text from PDF: #{e.message}"
      ensure
        txt&.unlink
      end
    end

    # ------------------------------------------------------------------
    # Header fields
    # ------------------------------------------------------------------

    def extract_invoice_number
      m = @text.match(/(?:facture|invoice)\s*n[°o]?\s*[:.]?\s*([A-Z0-9\-]+)/i)
      m ? m[1].strip : nil
    end

    def extract_issue_date
      m = @text.match(/(?:date\s*(?:de\s*)?facture|facture\s*du|date)\s*[:.]?\s*(\d{1,2}\s+[a-zéèêàô\-]+\s+\d{4}|\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i)
      return parse_french_date(m[1]) if m
      nil
    end

    def extract_due_date
      m = @text.match(/(?:échéance|date\s*limite\s*de\s*règlement|due\s*date)\s*[:.]?\s*(\d{1,2}\s+[a-zéèêàô\-]+\s+\d{4}|\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i)
      return parse_french_date(m[1]) if m
      nil
    end

    def extract_note
      m = @text.match(/(?:objet|note|subject)\s*[:.]?\s*(.+?)(?:\n|$)/i)
      m ? m[1].strip : nil
    end

    # ------------------------------------------------------------------
    # Seller
    # ------------------------------------------------------------------

    def extract_seller
      h = {}

      # Block before "FACTURE"
      boundary = @lines.find_index { |l| l =~ /^\s*(FACTURE|Invoice)/i } || 5
      block = @lines[0...boundary]

      h[:name]        = block.find { |l| l.length > 2 && l !~ /^\d/ }&.strip
      h[:street_name] = block.find { |l| l =~ /^\d+\s+(rue|avenue|boulevard|allée|chemin|place|impasse|route)/i }&.strip

      cp_city = block.find { |l| l =~ /^(\d{5})\s+(.+)/ }
      if cp_city
        m = cp_city.match(/^(\d{5})\s+(.+)/)
        h[:postal_zone] = m[1]
        h[:city_name]   = m[2].strip
      end

      h[:country_code] = "FR"

      # Legal IDs from full text
      # Extract buyer TVA first so we don't confuse it with seller TVA
      buyer_vat = nil
      m = @text.match(/Client\b.*?N°\s*TVA\s*[:.]?\s*([A-Z]{2}\d{9,11})/im)
      buyer_vat = m[1] if m

      all_tva = @text.scan(/N°\s*TVA\s*[:.]?\s*([A-Z]{2}\d{9,11})/i).flatten
      seller_tva = all_tva.find { |t| t != buyer_vat }
      h[:vat_identifier] = seller_tva if seller_tva

      # SIREN: with prefix or just "digits RCS"
      m = @text.match(/(?:SIREN|RCS)\s*[:.]?\s*(\d{9})/i)
      h[:legal_registration_id] = m[1] if m

      unless h[:legal_registration_id]
        m = @text.match(/(\d{9})\s+RCS\b/i)
        h[:legal_registration_id] = m[1] if m
      end

      m = @text.match(/IBAN\s*[:.]?\s*([A-Z]{2}\d{2}[\s\d]+)/i)
      h[:iban] = m[1].gsub(/\s/, "") if m

      m = @text.match(/BIC\s*[:.]?\s*([A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?)/i)
      h[:bic] = m[1] if m

      m = @text.match(/Email\s*[:.]?\s*([\w\.\-]+@[\w\.\-]+\.[a-z]{2,})/i)
      h[:electronic_address] = m[1] if m

      h
    end

    # ------------------------------------------------------------------
    # Buyer
    # ------------------------------------------------------------------

    def extract_buyer
      h = {}

      # "Client" line may have inline IDs
      client_line = @lines.find { |l| l =~ /^Client\b/i }
      if client_line
        m = client_line.match(/Client\s*[-\u2013\u2014]?\s*(?:N\u00b0\s*TVA\s*[:.]?\s*([A-Z]{2}\d{9,11}))?\s*(?:[-\u2013\u2014]?\s*SIRET\s*[:.]?\s*(\d{14}))?/i)
        h[:vat_identifier]      = m[1] if m && m[1]
        h[:legal_registration_id] = m[2] if m && m[2]
      end

      # Block between FACTURE and "Objet" / table header
      facture_idx = @lines.find_index { |l| l =~ /^\s*(FACTURE|Invoice)/i }
      return h unless facture_idx

      end_idx = @lines.find_index { |l| l =~ /^(Objet|Désignation|Client\b)/i }
      end_idx ||= facture_idx + 8
      block = @lines[facture_idx...end_idx]

      clean = block.reject { |l| l =~ /^(FACTURE|Date\s*:|N°)/i }

      # Name often sits just before the FACTURE line
      prev = facture_idx > 0 ? @lines[facture_idx - 1] : nil
      if prev && prev.length > 2 && prev !~ /^\d{5}\b/
        h[:name] = prev.strip
      end

      # Address in the buyer block
      addr = clean.find { |l| l =~ /^\d+\s+(rue|avenue|boulevard|allée|chemin|place|impasse|route)/i }
      h[:street_name] = addr&.strip

      cp_city = clean.find { |l| l =~ /^(\d{5})\b/ }
      if cp_city
        m = cp_city.match(/^(\d{5})\s*(.*)/)
        h[:postal_zone] = m[1]
        city = m[2].strip
        h[:city_name] = city unless city.empty?
      end

      h[:country_code] = "FR"

      # Fallback IDs from full text
      unless h[:vat_identifier]
        all_tva = @text.scan(/N°\s*TVA\s*[:.]?\s*([A-Z]{2}\d{9,11})/i).flatten
        h[:vat_identifier] = all_tva.last if all_tva.size > 1
      end
      unless h[:legal_registration_id]
        m = @text.match(/SIRET\s*[:.]?\s*(\d{14})/i)
        h[:legal_registration_id] = m[1] if m
      end

      h
    end

    # ------------------------------------------------------------------
    # Line items
    # ------------------------------------------------------------------

    ITEM_RE = %r{
      (?<tax>[\d\s]+[,\.][\d]+)\s*%?\s+
      (?<price>[\d\s]+[,\.][\d]+)\s*€?\s+
      (?<qty>\d+)\s+
      (?<total>[\d\s]+[,\.][\d]+)\s*€?
    }x

    def extract_line_items
      items = []
      buffer = []
      in_table = false

      @lines.each do |line|
        if line =~ /Désignation/ && line =~ /%\s*TVA/
          in_table = true
          buffer = []
          next
        end

        next unless in_table
        break if line =~ /^(Total\s*HT|TVA\s+\d|TOTAL\s*TTC)/i

        m = line.match(ITEM_RE)
        if m && buffer.any?
          buffer.reject! { |b| b =~ /^Client\b/i || b =~ /TVA.*SIRET/ }

          name  = buffer.shift&.strip
          desc  = buffer.join(" ").strip
          buffer = []

          items << {
            id:                (items.length + 1).to_s,
            name:              name,
            description:       desc.empty? ? nil : desc,
            quantity:          m[:qty].to_i,
            unit_code:         "C62",
            price_amount:      parse_amount(m[:price]),
            line_total_amount: parse_amount(m[:total]),
            tax_percent:       parse_amount(m[:tax]).to_f,
            tax_category:      "S"
          }
        elsif line =~ /^[A-ZÀ-ÿ#\-]/ && line !~ /^(Total|TVA|Désignation|Objet)/i
          buffer << line
        else
          buffer = []
        end
      end

      items
    end

    # ------------------------------------------------------------------
    # Totals
    # ------------------------------------------------------------------

    def compute_totals(items)
      line_ext = items.sum { |i| i[:line_total_amount] || 0 }
      tax_amt  = 0

      # Prefer extracted totals from text
      m = @text.match(/Total\s*HT\s+([\d\s]+[,\.][\d]+)/i)
      line_ext = parse_amount(m[1]) if m

      m = @text.match(/TVA\s+\d+[,\.]?\d*\s*%?\s+([\d\s]+[,\.][\d]+)/i)
      tax_amt = parse_amount(m[1]) if m

      m = @text.match(/TOTAL\s*TTC\s+([\d\s]+[,\.][\d]+)/i)
      tax_inc = m ? parse_amount(m[1]) : (line_ext + tax_amt)

      {
        line_extension: line_ext,
        tax_amount:     tax_amt,
        tax_exclusive:  line_ext,
        tax_inclusive:  tax_inc,
        payable:        tax_inc
      }
    end

    def build_tax_breakdown(totals)
      return [] unless totals[:line_extension] && totals[:tax_amount]

      rate = 20.0
      m = @text.match(/TVA\s+([\d\s]+[,\.][\d]+)\s*%/i)
      rate = parse_amount(m[1]).to_f if m

      [{
        taxable_amount: totals[:line_extension],
        tax_amount:     totals[:tax_amount],
        tax_percent:    rate,
        tax_category:   "S"
      }]
    end

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    FRENCH_MONTHS = {
      "janvier" => 1, "février" => 2, "mars" => 3, "avril" => 4,
      "mai" => 5, "juin" => 6, "juillet" => 7, "août" => 8,
      "septembre" => 9, "octobre" => 10, "novembre" => 11, "décembre" => 12
    }.freeze

    def parse_french_date(str)
      str = str.to_s.strip.downcase
      m = str.match(/(\d{1,2})\s+([a-zéèêàô\-]+)\s+(\d{4})/)
      if m
        day, month_name, year = m[1].to_i, m[2], m[3].to_i
        month = FRENCH_MONTHS[month_name]
        return Date.new(year, month, day) if month
      end
      ["%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y", "%Y-%m-%d"].each do |fmt|
        return Date.strptime(str, fmt)
      rescue ArgumentError
        next
      end
      nil
    end

    def parse_amount(str)
      str.to_s.gsub(/\s/, "").gsub(",", ".").to_d
    rescue
      nil
    end
  end
end
