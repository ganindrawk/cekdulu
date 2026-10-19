"""Ubah spreadsheet katalog CekDulu (xlsx) menjadi SQL INSERT idempotent.

Alur yang disepakati dengan Kan:
  Kan mengisi kolom link_affiliate di spreadsheet -> mengembalikan file ke Kai ->
  script ini mengubahnya menjadi SQL -> Kan menjalankan sekali di Supabase SQL Editor.

Pemetaan kolom -> tabel:
  products:        name, description, image_url, marketplace, marketplace_url,
                  barcode (opsional, kolom ke-10 "barcode"), price, rating,
                  review_count
  affiliate_links: product_id (dicocokkan via marketplace+marketplace_url),
                  marketplace, original_url, affiliate_url

Idempoten: aman dijalankan ulang. Produk di-upsert memakai kunci bisnis
(marketplace, marketplace_url); link affiliate untuk produk di file ini
dihapus lalu disisipkan ulang, sehingga isi file selalu menjadi kebenaran.

Jalankan:
  python3 xlsx_to_catalog_sql.py [input.xlsx] [output.sql]
Default input : ~/workspace/your_files/katalog-cekdulu-beauty.xlsx
Default output: <input>.sql (satu folder dengan input)
"""
import os
import re
import sys
import urllib.parse
from datetime import datetime, timezone

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

# Kolom opsional: bila header ke-10 adalah "barcode", nilainya dibaca.
# File lama (9 kolom) tetap valid.
OPTIONAL_BARCODE_HEADER = "barcode"

VALID_MARKETPLACES = ("shopee", "tokopedia")

# Heuristik validator link affiliate. Link affiliate Shopee/Tokopedia yang dibuat
# lewat dashboard keluar sebagai short-link (shope.ee, tokopedia.link, dsb.)
# atau URL berparameter tracking; URL produk biasa (shopee.co.id/...-i.123.456)
# yang salah tempel berarti komisi nol.
AFFILIATE_HOSTS = {
    "shopee": ("shope.ee", "shp.ee", "s.shopee.co.id"),
    "tokopedia": ("tokopedia.link", "tk.tokopedia.com"),
}
PLAIN_PRODUCT_HOSTS = {
    "shopee": ("shopee.co.id", "www.shopee.co.id"),
    "tokopedia": ("tokopedia.com", "www.tokopedia.com"),
}
AFFILIATE_QUERY_MARKERS = (
    "af_click_id", "smtt=", "sp_atk=", "aff_id", "affiliate", "utm_medium=aff",
)


def looks_like_affiliate_link(link, marketplace):
    """True  = tampak seperti link affiliate,
       False = tampak seperti URL produk biasa (komisi nol),
       None  = tidak bisa dipastikan (heuristik, bukan vonis)."""
    try:
        u = urllib.parse.urlparse(link)
    except Exception:
        return None
    host = (u.netloc or "").lower().split(":")[0]
    if not host:
        return None
    if host in AFFILIATE_HOSTS.get(marketplace, ()):
        return True
    q = (u.query or "").lower()
    if any(m in q for m in AFFILIATE_QUERY_MARKERS):
        return True
    if host in PLAIN_PRODUCT_HOSTS.get(marketplace, ()):
        return False
    return None


def sql_str(value):
    if value is None:
        return "NULL"
    s = str(value).strip()
    if not s:
        return "NULL"
    return "'" + s.replace("'", "''") + "'"


def sql_num(value, integer=False):
    if value is None:
        return "NULL"
    s = str(value).strip().replace(",", "").replace(" ", "")
    if not s:
        return "NULL"
    try:
        n = int(float(s)) if integer else float(s)
    except ValueError:
        raise ValueError(f"nilai angka tidak valid: {value!r}")
    return str(int(n)) if integer else repr(n)


def norm_url(value):
    if value is None:
        return None
    s = str(value).strip()
    return s or None


def main():
    default_in = os.path.expanduser("~/workspace/your_files/katalog-cekdulu-beauty.xlsx")
    in_path = sys.argv[1] if len(sys.argv) > 1 else default_in
    out_path = sys.argv[2] if len(sys.argv) > 2 else re.sub(r"\.xlsx$", ".sql", in_path)

    wb = load_workbook(in_path, data_only=True)
    ws = wb.active

    got = [c.value for c in ws[1]]
    has_barcode = (
        len(got) == len(HEADERS) + 1 and got[-1] == OPTIONAL_BARCODE_HEADER
    )
    if not has_barcode and got != HEADERS:
        sys.exit(f"ERROR: header tidak sesuai.\n  diharapkan: {HEADERS}\n  ditemukan : {got}")

    rows, warnings = [], []
    for r in range(2, ws.max_row + 1):
        ncols = len(HEADERS) + (1 if has_barcode else 0)
        vals = [ws.cell(row=r, column=c).value for c in range(1, ncols + 1)]
        if all(v is None or str(v).strip() == "" for v in vals):
            continue  # baris kosong, lewati
        nama, mp, url, harga, rating, ulasan, link, gambar, desk = vals[:9]
        barcode = vals[9] if has_barcode else None

        if not nama or not str(nama).strip():
            warnings.append(f"baris {r}: nama_produk kosong -> dilewati")
            continue
        mp = str(mp).strip().lower() if mp else ""
        if mp not in VALID_MARKETPLACES:
            warnings.append(f"baris {r}: marketplace '{mp}' tidak valid -> dilewati")
            continue
        url = norm_url(url)
        if not url:
            sys.exit(f"ERROR: baris {r} ({nama}): url_asli wajib diisi (kunci pencocokan scan).")
        link = norm_url(link)
        if link:
            verdict = looks_like_affiliate_link(link, mp)
            if verdict is False:
                warnings.append(
                    f"baris {r} ({nama}): link_affiliate tampak seperti URL produk "
                    f"BIASA (bukan link affiliate) -> komisi NOL bila dipakai: {link}"
                )

        rows.append({
            "excel_row": r,
            "name": str(nama).strip(),
            "description": (str(desk).strip() or None) if desk else None,
            "image_url": norm_url(gambar),
            "marketplace": mp,
            "marketplace_url": url,
            "barcode": (str(barcode).strip() or None) if barcode is not None else None,
            "price": sql_num(harga),
            "rating": sql_num(rating),
            "review_count": sql_num(ulasan, integer=True),
            "affiliate_url": link,
        })

    # deteksi duplikat kunci bisnis di dalam file
    seen = {}
    for row in rows:
        key = (row["marketplace"], row["marketplace_url"])
        if key in seen:
            warnings.append(f"baris {row['excel_row']}: duplikat marketplace_url dengan baris {seen[key]}")
        else:
            seen[key] = row["excel_row"]

    with_links = sum(1 for row in rows if row["affiliate_url"])
    without_links = len(rows) - with_links
    suspicious = sum(
        1
        for w in warnings
        if "bukan link affiliate" in w
    )

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    L = []
    A = L.append
    A("-- ===============================================================================")
    A("-- CekDulu: import katalog produk dari spreadsheet")
    A(f"-- Dibuat  : {now} oleh tools/xlsx_to_catalog_sql.py")
    A(f"-- Sumber  : {os.path.basename(in_path)}")
    A(f"-- Isi     : {len(rows)} produk ({with_links} dengan link affiliate, "
      f"{without_links} tanpa link)")
    if suspicious:
        A(f"-- PERINGATAN: {suspicious} link_affiliate tampak seperti URL produk biasa "
          f"(bukan link affiliate) - lihat output console, komisi NOL bila dipakai.")
    A("-- Sifat   : idempotent, aman dijalankan ulang di Supabase SQL Editor.")
    A("-- ===============================================================================")
    A("")
    A("BEGIN;")
    A("")
    A("-- Tabel staging sementara (dihapus otomatis saat COMMIT).")
    A("CREATE TEMP TABLE _cekdulu_import (")
    A("  seq             INTEGER,")
    A("  name            TEXT,")
    A("  description     TEXT,")
    A("  image_url       TEXT,")
    A("  marketplace     TEXT,")
    A("  marketplace_url TEXT,")
    A("  barcode           TEXT,")
    A("  price           NUMERIC,")
    A("  rating          NUMERIC,")
    A("  review_count    INTEGER,")
    A("  affiliate_url   TEXT")
    A(") ON COMMIT DROP;")
    A("")
    for i, row in enumerate(rows, start=1):
        A(
            "INSERT INTO _cekdulu_import (seq, name, description, image_url, marketplace, "
            "marketplace_url, barcode, price, rating, review_count, affiliate_url) VALUES "
            f"({i}, {sql_str(row['name'])}, {sql_str(row['description'])}, "
            f"{sql_str(row['image_url'])}, '{row['marketplace']}', "
            f"{sql_str(row['marketplace_url'])}, {sql_str(row['barcode'])}, "
            f"{row['price']}, {row['rating']}, "
            f"{row['review_count']}, {sql_str(row['affiliate_url'])});"
        )
    A("")
    A("-- 1) Upsert produk memakai kunci bisnis (marketplace, marketplace_url).")
    A("INSERT INTO public.products")
    A("  (name, description, image_url, marketplace, marketplace_url, barcode, price,")
    A("   rating, review_count, data_refreshed_at)")
    A("SELECT name, description, image_url, marketplace, marketplace_url, barcode,")
    A("       price, rating, review_count, now()")
    A("FROM _cekdulu_import")
    A("ON CONFLICT (marketplace, marketplace_url) WHERE marketplace_url IS NOT NULL")
    A("DO UPDATE SET")
    A("  name              = EXCLUDED.name,")
    A("  description       = EXCLUDED.description,")
    A("  image_url         = EXCLUDED.image_url,")
    A("  barcode           = EXCLUDED.barcode,")
    A("  price             = EXCLUDED.price,")
    A("  rating            = EXCLUDED.rating,")
    A("  review_count      = EXCLUDED.review_count,")
    A("  data_refreshed_at = now();")
    A("")
    A("-- 2) Segarkan link affiliate: hapus yang lama untuk produk di file ini,")
    A("--    lalu sisipkan yang baru (hanya baris yang punya link_affiliate).")
    A("DELETE FROM public.affiliate_links al")
    A("USING _cekdulu_import i")
    A("JOIN public.products p")
    A("  ON p.marketplace = i.marketplace AND p.marketplace_url = i.marketplace_url")
    A("WHERE al.product_id = p.id")
    A("  AND i.affiliate_url IS NOT NULL;")
    A("")
    A("INSERT INTO public.affiliate_links")
    A("  (product_id, marketplace, original_url, affiliate_url, status)")
    A("SELECT p.id, i.marketplace, i.marketplace_url, i.affiliate_url, 'active'")
    A("FROM _cekdulu_import i")
    A("JOIN public.products p")
    A("  ON p.marketplace = i.marketplace AND p.marketplace_url = i.marketplace_url")
    A("WHERE i.affiliate_url IS NOT NULL;")
    A("")
    A("COMMIT;")
    A("")
    A("-- Verifikasi cepat setelah jalan (opsional):")
    A("-- SELECT marketplace, count(*) FROM public.products GROUP BY 1;")
    A("-- SELECT count(*) FROM public.affiliate_links WHERE status = 'active';")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")

    print(f"OK: {out_path}")
    print(f"  produk: {len(rows)} | dengan link affiliate: {with_links} | tanpa link: {without_links}"
          f" | mencurigakan (bukan affiliate): {suspicious}")
    for w in warnings:
        print(f"  PERINGATAN: {w}")
    if without_links:
        print("  CATATAN: baris tanpa link_affiliate tetap diimpor sebagai produk, "
              "tapi belum punya link affiliate.")


if __name__ == "__main__":
    main()
