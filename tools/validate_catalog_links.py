"""Validasi kolom link_affiliate spreadsheet katalog CekDulu sebelum dikonversi ke SQL.

Latar: kesalahan paling merugikan di tahap ini adalah menempel URL produk biasa
(bukan link affiliate) ke kolom link_affiliate — link-nya tetap "jalan" tapi
komisi NOL dan kesalahannya tidak terlihat. Script ini menangkap itu sebelum
file diubah menjadi SQL INSERT oleh xlsx_to_catalog_sql.py.

Aturan (heuristik, konservatif):
  - kosong            -> SKIP  (produk tetap diimpor tanpa link affiliate)
  - bukan URL         -> ERROR
  - sama dengan url_asli (atau URL produk yang sama tanpa parameter) -> ERROR
  - shopee: host s.shopee.co.id (hasil "Link Khusus"/Share to Earn), atau
    mengandung penanda affiliate (sp_atk, af_siteid, affiliate) -> OK,
    selain itu -> WARN
  - tokopedia: host tokopedia.link, atau mengandung penanda (ref, affiliate)
    -> OK, selain itu -> WARN
  - link yang sama dipakai di >1 baris -> WARN (kemungkinan salah tempel)

Jalankan:
  python3 validate_catalog_links.py [input.xlsx]
Keluar dengan kode 1 bila ada ERROR, 0 bila hanya SKIP/WARN/OK.
"""
import os
import re
import sys
from urllib.parse import urlparse, parse_qsl

from openpyxl import load_workbook

HEADERS = [
    "nama_produk",
    "marketplace",
    "url_asli",
    "harga",
    "rating",
    "jumlah_ulasan",
    "link_affiliate",
    "url_gambar",
    "deskripsi",
]

SHOPEE_AFFILIATE_HOSTS = {"s.shopee.co.id"}
SHOPEE_AFFILIATE_MARKERS = ("sp_atk", "af_siteid", "affiliate", "xptdk")
TOKOPEDIA_AFFILIATE_HOSTS = {"tokopedia.link", "www.tokopedia.link"}
TOKOPEDIA_AFFILIATE_MARKERS = ("affiliate",)


def norm_url(value):
    if value is None:
        return None
    s = str(value).strip()
    return s or None


def strip_query(url):
    """URL tanpa query/fragment, untuk membandingkan URL produk vs link."""
    p = urlparse(url)
    host = p.netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    path = p.path.rstrip("/")
    return f"{p.scheme}://{host}{path}"


def looks_like_url(s):
    return bool(re.match(r"^https?://\S+$", s, re.IGNORECASE))


def check_row(nama, mp, url_asli, link):
    """Kembalikan (status, pesan). status: OK/WARN/ERROR/SKIP."""
    if not link:
        return "SKIP", "link_affiliate kosong — produk diimpor tanpa link affiliate"
    if not looks_like_url(link):
        return "ERROR", f"bukan URL valid: {link!r}"
    p = urlparse(link)
    host = p.netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    qkeys = {k.lower() for k, _ in parse_qsl(p.query)}
    blob = (link + " " + p.query).lower()

    markers = SHOPEE_AFFILIATE_MARKERS if mp == "shopee" else TOKOPEDIA_AFFILIATE_MARKERS
    has_marker = any(m in qkeys or m in blob for m in markers)

    if url_asli and strip_query(link) == strip_query(url_asli):
        # Basis URL sama dengan url_asli: hanya sah bila query membawa
        # penanda affiliate (mis. ?sp_atk=...). Tanpa itu = URL produk biasa.
        if has_marker:
            return "OK", "URL produk dengan penanda affiliate di query"
        return ("ERROR",
                "link_affiliate SAMA dengan url_asli — ini URL produk biasa, "
                "komisi affiliate NOL. Tempel link hasil 'Link Khusus'/Share to Earn.")

    if mp == "shopee":
        if host in SHOPEE_AFFILIATE_HOSTS:
            return "OK", "short link affiliate Shopee (s.shopee.co.id)"
        if any(m in qkeys or m in blob for m in SHOPEE_AFFILIATE_MARKERS):
            return "OK", "mengandung penanda affiliate Shopee"
        return ("WARN",
                "tidak terlihat seperti link affiliate Shopee "
                "(bukan s.shopee.co.id dan tanpa penanda sp_atk/af_siteid) — "
                "pastikan ini link hasil 'Link Khusus', bukan URL produk biasa")
    if mp == "tokopedia":
        if host in TOKOPEDIA_AFFILIATE_HOSTS:
            return "OK", "short link Tokopedia (tokopedia.link)"
        if any(m in qkeys or m in blob for m in TOKOPEDIA_AFFILIATE_MARKERS):
            return "OK", "mengandung penanda affiliate Tokopedia"
        return ("WARN",
                "tidak terlihat seperti link affiliate Tokopedia "
                "(bukan tokopedia.link dan tanpa penanda) — pastikan dari dashboard affiliate")
    return "WARN", f"marketplace '{mp}' tidak dikenali"


def main():
    default_in = os.path.expanduser("~/workspace/your_files/katalog-cekdulu-beauty.xlsx")
    in_path = sys.argv[1] if len(sys.argv) > 1 else default_in

    wb = load_workbook(in_path, data_only=True)
    ws = wb.active
    got = [c.value for c in ws[1]]
    if got != HEADERS:
        sys.exit(f"ERROR: header tidak sesuai.\n  diharapkan: {HEADERS}\n  ditemukan : {got}")

    results = []
    seen_links = {}
    for r in range(2, ws.max_row + 1):
        vals = [ws.cell(row=r, column=c).value for c in range(1, 10)]
        if all(v is None or str(v).strip() == "" for v in vals):
            continue
        nama, mp, url_asli, _, _, _, link, _, _ = vals
        nama = str(nama).strip() if nama else f"(baris {r})"
        mp = str(mp).strip().lower() if mp else ""
        link = norm_url(link)
        status, msg = check_row(nama, mp, norm_url(url_asli), link)
        results.append((r, nama, status, msg))
        if link and status in ("OK", "WARN"):
            key = strip_query(link)
            seen_links.setdefault(key, []).append(r)

    dup_warnings = []
    for key, rows in seen_links.items():
        if len(rows) > 1:
            dup_warnings.append(
                f"link yang sama dipakai di baris {', '.join(map(str, rows))} "
                f"— kemungkinan salah tempel")

    n_ok = sum(1 for _, _, s, _ in results if s == "OK")
    n_warn = sum(1 for _, _, s, _ in results if s == "WARN")
    n_err = sum(1 for _, _, s, _ in results if s == "ERROR")
    n_skip = sum(1 for _, _, s, _ in results if s == "SKIP")

    print(f"Validasi link_affiliate: {os.path.basename(in_path)}")
    print(f"  OK: {n_ok} | WARN: {n_warn} | ERROR: {n_err} | kosong: {n_skip}")
    for r, nama, status, msg in results:
        if status != "OK":
            print(f"  [{status}] baris {r} ({nama}): {msg}")
    for w in dup_warnings:
        print(f"  [WARN] {w}")

    if n_err:
        print("\nAda ERROR — perbaiki dulu sebelum konversi ke SQL.")
        return 1
    if n_warn or dup_warnings:
        print("\nAda WARN — periksa manual; aman dilanjut bila link memang benar.")
    else:
        print("\nBersih — siap dikonversi ke SQL.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
