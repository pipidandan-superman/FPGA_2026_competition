# Extract text from the vendor PDFs (AT command set + module manual).
import sys

from pypdf import PdfReader

for path in sys.argv[1:]:
    print("=" * 78)
    print("FILE:", path)
    print("=" * 78)
    r = PdfReader(path)
    print("[pages] %d" % len(r.pages))
    for i, pg in enumerate(r.pages):
        txt = pg.extract_text() or ""
        print("----- page %d -----" % (i + 1))
        print(txt)
