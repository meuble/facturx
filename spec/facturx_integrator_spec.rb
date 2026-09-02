require 'spec_helper'

RSpec.describe FacturXIntegrator do
  let(:config) { Config.new }
  let(:integrator) { FacturXIntegrator.new(config) }
  let(:temp_dir) { File.join(__dir__, '..', 'tmp') }

  before do
    FileUtils.mkdir_p(temp_dir)
  end

  after do
    FileUtils.rm_f(Dir.glob(File.join(temp_dir, '*')))
  end

  describe "#initialize" do
    it "accepts a config object" do
      expect { FacturXIntegrator.new(config) }.not_to raise_error
    end
  end

  describe "#integrate_with_qpdf" do
    it "raises error when qpdf is not available" do
      # Mock system call to return false
      allow_any_instance_of(Object).to receive(:system).and_return(false)
      
      expect {
        integrator.integrate_with_qpdf('/tmp/test.pdf', '/tmp/test.xml', '/tmp/output.pdf')
      }.to raise_error(/qpdf n'est pas installé/)
    end

    it "uses qpdf to embed XML in PDF when available" do
      if system('which qpdf > /dev/null 2>&1')
        pdf_path = File.join(temp_dir, 'test.pdf')
        xml_path = File.join(temp_dir, 'test.xml')
        output_path = File.join(temp_dir, 'test_facturx.pdf')
        
        # Create a simple PDF
        File.write(pdf_path, '%PDF-1.3\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj\nxref\n0 4\n0000000000 65535 f \n0000000010 00000 n \n0000000079 00000 n \n0000000138 00000 n \ntrailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n178\n%%EOF')
        File.write(xml_path, '<?xml version="1.0"?><test>XML content</test>')
        
        # Use qpdf to fix the PDF first
        fixed_pdf = File.join(temp_dir, 'test_fixed.pdf')
        result = system("qpdf --empty --pages #{pdf_path} 1 -- #{fixed_pdf} 2>/dev/null")
        if result && File.exist?(fixed_pdf)
          File.rename(fixed_pdf, pdf_path)
        end
        
        result = integrator.integrate_with_qpdf(pdf_path, xml_path, output_path)
        expect(result).to eq(output_path)
        expect(File.exist?(output_path)).to be true
        
        # Verify attachment was added
        attachments = `qpdf --list-attachments #{output_path} 2>&1`
        expect(attachments).to include('test.xml')
      else
        skip "qpdf not installed"
      end
    end
  end

  describe "#integrate" do
    it "attempts to use zugpferd first and falls back to qpdf" do
      if system('which qpdf > /dev/null 2>&1')
        pdf_path = File.join(temp_dir, 'test.pdf')
        xml_path = File.join(temp_dir, 'test.xml')
        output_path = File.join(temp_dir, 'test_facturx.pdf')
        
        # Create files
        File.write(pdf_path, '%PDF-1.3\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj\nxref\n0 4\n0000000000 65535 f \n0000000010 00000 n \n0000000079 00000 n \n0000000138 00000 n \ntrailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n178\n%%EOF')
        File.write(xml_path, '<?xml version="1.0"?><test>XML content</test>')
        
        # Fix the PDF first
        fixed_pdf = File.join(temp_dir, 'test_fixed.pdf')
        result = system("qpdf --empty --pages #{pdf_path} 1 -- #{fixed_pdf} 2>/dev/null")
        if result && File.exist?(fixed_pdf)
          File.rename(fixed_pdf, pdf_path)
        end
        
        # Mock zugpferd to raise an error so it falls back to qpdf
        allow(Zugpferd::CII::Reader).to receive(:new).and_raise(StandardError.new("zugpferd error"))
        
        result = integrator.integrate(pdf_path, xml_path, output_path)
        expect(result).to eq(output_path)
        expect(File.exist?(output_path)).to be true
      else
        skip "qpdf not installed"
      end
    end

    it "creates output file with default path" do
      if system('which qpdf > /dev/null 2>&1')
        pdf_path = File.join(temp_dir, 'test.pdf')
        xml_path = File.join(temp_dir, 'test.xml')
        
        # Create files
        File.write(pdf_path, '%PDF-1.3\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj\nxref\n0 4\n0000000000 65535 f \n0000000010 00000 n \n0000000079 00000 n \n0000000138 00000 n \ntrailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n178\n%%EOF')
        File.write(xml_path, '<?xml version="1.0"?><test>XML content</test>')
        
        # Fix the PDF first
        fixed_pdf = File.join(temp_dir, 'test_fixed.pdf')
        result = system("qpdf --empty --pages #{pdf_path} 1 -- #{fixed_pdf} 2>/dev/null")
        if result && File.exist?(fixed_pdf)
          File.rename(fixed_pdf, pdf_path)
        end
        
        allow(Zugpferd::CII::Reader).to receive(:new).and_raise(StandardError.new("zugpferd error"))
        
        result = integrator.integrate(pdf_path, xml_path)
        expected_output = pdf_path.sub(/\.pdf$/i, '_facturx.pdf')
        expect(result).to eq(expected_output)
        expect(File.exist?(expected_output)).to be true
      else
        skip "qpdf not installed"
      end
    end

    it "uses custom output path when provided" do
      if system('which qpdf > /dev/null 2>&1')
        pdf_path = File.join(temp_dir, 'test.pdf')
        xml_path = File.join(temp_dir, 'test.xml')
        custom_output = File.join(temp_dir, 'custom_output.pdf')
        
        # Create files
        File.write(pdf_path, '%PDF-1.3\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj\nxref\n0 4\n0000000000 65535 f \n0000000010 00000 n \n0000000079 00000 n \n0000000138 00000 n \ntrailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n178\n%%EOF')
        File.write(xml_path, '<?xml version="1.0"?><test>XML content</test>')
        
        # Fix the PDF first
        fixed_pdf = File.join(temp_dir, 'test_fixed.pdf')
        result = system("qpdf --empty --pages #{pdf_path} 1 -- #{fixed_pdf} 2>/dev/null")
        if result && File.exist?(fixed_pdf)
          File.rename(fixed_pdf, pdf_path)
        end
        
        allow(Zugpferd::CII::Reader).to receive(:new).and_raise(StandardError.new("zugpferd error"))
        
        result = integrator.integrate(pdf_path, xml_path, custom_output)
        expect(result).to eq(custom_output)
        expect(File.exist?(custom_output)).to be true
      else
        skip "qpdf not installed"
      end
    end
  end
end
