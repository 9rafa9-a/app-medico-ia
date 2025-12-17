import pdfplumber
import re
from unidecode import unidecode
import io
import logging

# Suppress noisy PDF warnings matches
logging.getLogger("pdfminer").setLevel(logging.ERROR)

class HeuristicParser:
    def __init__(self):
        pass

    def extract_optimized_context(self, file_bytes: bytes) -> str:
        """
        Extracts content from PDF bytes with Python-side optimization:
        1. Prioritizes Tables (converts to CSV-like format).
        2. Extracts clean text from non-table areas.
        3. Removes headers/footers/page numbers.
        Returns a single optimized string payload.
        """
        full_context = []
        
        try:
            with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
                for i, page in enumerate(pdf.pages):
                    # 1. Table Extraction (High Fidelity)
                    # Use lighter settings to speed up
                    tables = page.extract_tables()
                    if tables:
                        for table in tables:
                            # Filter empty rows/cols and format as CSV
                            clean_rows = []
                            for row in table:
                                clean_row = [str(cell).strip().replace('\n', ' ') for cell in row if cell]
                                if clean_row:
                                    clean_rows.append(" | ".join(clean_row))
                            if clean_rows:
                                full_context.append(f"[TABELA PÁGINA {i+1}]\n" + "\n".join(clean_rows))
                    
                    # 2. Text Extraction (Fallback/Complementary)
                    text = page.extract_text()
                    if text:
                        # Cleaning: Remove common header/footer patterns
                        lines = text.split('\n')
                        filtered_lines = []
                        for line in lines:
                            # Ignore page numbers e.g. "17 de 40" or just "17"
                            if re.match(r'^\d+(\s?de\s?\d+)?$', line.strip()):
                                continue
                            # Ignore common footer junk (short lines with no numbers/meaning)
                            if len(line.strip()) < 5: 
                                continue
                            filtered_lines.append(line)
                        
                        full_context.append(f"[TEXTO PÁGINA {i+1}]\n" + "\n".join(filtered_lines))
                        
        except Exception as e:
            print(f"Erro no parser otimizado: {e}")
            return ""

        return "\n\n".join(full_context)

    # Helper for legacy calls (should not be used in new flow, but good for safety)
    def extract_legacy_heuristic(self, file_bytes: bytes):
        return []
