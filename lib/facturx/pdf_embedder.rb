# frozen_string_literal: true

require "hexapdf"

module FacturX
  # Embeds a Factur-X XML into an existing PDF, producing a PDF/A-3
  # conformant hybrid invoice. Uses HexaPDF to write the low-level
  # structures (EmbeddedFiles name tree, AF array, XMP metadata,
  # OutputIntent).
  class PdfEmbedder
    FACTURX_FILENAME = "factur-x.xml"

    # XMP template for Factur-X / PDF/A-3b
    XMP_TEMPLATE = <<~XMP
      <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/">
            <pdfaid:part>3</pdfaid:part>
            <pdfaid:conformance>b</pdfaid:conformance>
          </rdf:Description>
          <rdf:Description rdf:about="" xmlns:fx="urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#">
            <fx:DocumentType>INVOICE</fx:DocumentType>
            <fx:DocumentFileName>factur-x.xml</fx:DocumentFileName>
            <fx:Version>1.0</fx:Version>
            <fx:ConformanceLevel>%{conformance_level}</fx:ConformanceLevel>
          </rdf:Description>
        </rdf:RDF>
      </x:xmpmeta>
      <?xpacket end="w"?>
    XMP

    def initialize(xml_content, conformance_level: "EN 16931")
      @xml_content        = xml_content
      @conformance_level  = conformance_level
    end

    # @param input_pdf_path [String] path to the source PDF
    # @param output_pdf_path [String] path for the generated Factur-X PDF
    def embed(input_pdf_path, output_pdf_path)
      raise "Input PDF not found: #{input_pdf_path}" unless File.exist?(input_pdf_path)

      # Strategy: create a fresh PDF 1.7 document and copy pages from source.
      # This avoids the issue where HexaPDF writes a 2.0 header when a
      # PDF 1.3 file is opened and modified in-place.
      src = HexaPDF::Document.open(input_pdf_path)
      doc = HexaPDF::Document.new
      doc.version = '1.7'

      # Copy all pages
      src.pages.each { |page| doc.pages << doc.import(page) }

      # 1. Embedded file stream
      ef = doc.add({ Type: :EmbeddedFile, Subtype: :"text#2Fxml" })
      ef.stream = @xml_content

      # 2. File specification
      filespec = doc.add({
        Type: :Filespec,
        F:    FACTURX_FILENAME,
        UF:   FACTURX_FILENAME,
        Desc: "Factur-X invoice"
      })
      filespec[:EF] = { F: ef }

      # 3. Names tree (EmbeddedFiles)
      # Use explicit {Type: :Names} dict instead of doc.catalog.names
      # to ensure /Type /Names is written in the PDF.
      names = doc.add({Type: :Names})
      doc.catalog[:Names] = names

      ef_tree = doc.add({Type: :Names})
      names[:EmbeddedFiles] = ef_tree

      # Build new names array, removing any pre-existing factur-x.xml entries
      existing = ef_tree[:Names]&.to_a || []
      cleaned = existing.each_slice(2).reject { |name, _| name == FACTURX_FILENAME }.flatten(1)
      ef_tree[:Names] = cleaned + [FACTURX_FILENAME, filespec]

      # 4. Associated Files (AF) on catalog
      af = doc.catalog[:AF]&.to_a || []
      doc.catalog[:AF] = af + [filespec]

      # 5. XMP metadata
      meta = doc.add({ Type: :Metadata, Subtype: :XML })
      meta.stream = format(XMP_TEMPLATE, conformance_level: @conformance_level)
      doc.catalog[:Metadata] = meta

      # 6. OutputIntent for PDF/A-3
      unless doc.catalog.key?(:OutputIntents)
        output_intent = doc.add({
          Type:                      :OutputIntent,
          S:                         :GTS_PDFA1,
          OutputConditionIdentifier: "sRGB IEC61966-2.1",
          Info:                      "sRGB IEC61966-2.1",
          RegistryName:              "http://www.color.org"
        })
        doc.catalog[:OutputIntents] = [output_intent]
      end

      doc.write(output_pdf_path)

      # Patch the file header to force PDF 1.7.
      # HexaPDF bumps the version to 2.0 because /AF (Associated Files)
      # is a PDF 2.0 feature, but Factur-X validators expect a 1.7 header.
      File.open(output_pdf_path, "r+b") do |f|
        header = f.read(20)
        if header.start_with?("%PDF-2.0")
          f.seek(0)
          f.write("%PDF-1.7")
        end
      end

      output_pdf_path
    end
  end
end
