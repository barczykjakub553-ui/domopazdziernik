#!/usr/bin/env python3
"""One-off: fetch product:brand meta per product -> adds 'brand' to products_full.json."""
import re, json, html, urllib.request, concurrent.futures as cf, sys, os
UA = {"User-Agent": "Mozilla/5.0 (Macintosh) domokoncept-mirror/1.0"}
HERE = os.path.dirname(os.path.abspath(__file__))
prods = json.load(open(os.path.join(HERE, "products_full.json"), encoding="utf-8"))
BRAND = re.compile(r'<meta property="product:brand" content="([^"]+)"')

def get(url):
    for _ in range(3):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read().decode("utf-8", "replace")
        except Exception:
            pass
    return ""

def enrich(p):
    m = BRAND.search(get(p["url"]))
    p["brand"] = html.unescape(m.group(1)).strip() if m else ""
    return p

with cf.ThreadPoolExecutor(max_workers=12) as ex:
    prods = list(ex.map(enrich, prods))
json.dump(prods, open(os.path.join(HERE, "products_full.json"), "w", encoding="utf-8"), ensure_ascii=False)
from collections import Counter
c = Counter(p["brand"] or "(none)" for p in prods)
for k, v in sorted(c.items(), key=lambda x: -x[1]):
    print(v, k, file=sys.stderr)
