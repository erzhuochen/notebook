from pathlib import Path

import pdfplumber
import pypdfium2 as pdfium


source = Path(r"C:\Users\erzhuochen\Downloads\陈卓尔的简历 (3).pdf")
output_dir = Path(r"C:\Users\erzhuochen\Desktop\笔记\面经学习\tmp\pdfs\resume_self_intro")

with pdfplumber.open(source) as pdf:
    pages = []
    for index, page in enumerate(pdf.pages, start=1):
        pages.append(f"===== PAGE {index} =====\n{page.extract_text(x_tolerance=2, y_tolerance=2) or ''}")
    (output_dir / "extracted.txt").write_text("\n\n".join(pages), encoding="utf-8")

document = pdfium.PdfDocument(source)
for index in range(len(document)):
    page = document[index]
    bitmap = page.render(scale=2.0)
    bitmap.to_pil().save(output_dir / f"page-{index + 1}.png")

print(f"pages={len(document)}")
print(output_dir / "extracted.txt")
