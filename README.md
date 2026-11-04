# SMART HRD — AI Powered Personnel Administration System
**Sistem Administrasi Kepegawaian Berbasis AI · v1.1 (Skrip SQL v2.1 · Edge Function v2.2 · Supabase + Gemini Hybrid) · Bahasa Indonesia**

> 📅 **Pembaruan 4 Nov 2026 (v1.1):** ① API key Gemini kini **tersimpan otomatis** — tidak hilang lagi setiap logout/login (slot penyimpanan khusus + sinkron server untuk Admin/Manajer HRD). ② Perbaikan penuh kesalahan **“Gemini menolak permintaan”** — Edge Function **v2.2** (WAJIB deploy ulang bila masih memakai versi lama), pesan kesalahan berkode + tombol 🔍 Diagnosa Kunci & Model.

## Isi Paket

| File | Fungsi |
|---|---|
| `SMART-HRD.html` | Aplikasi lengkap dalam 1 berkas (HTML5+CSS3+JS) — 10 modul, dashboard 16 statistik + 5 grafik, workflow persetujuan 7 tahap, 32 jenis surat & dokumen legal kepegawaian, MADANI HR Assistant |
| `supabase-schema.sql` | **Kode lengkap untuk Supabase SQL Editor (v2.1)** — 12 tabel (profiles, pegawai, surat, dokumen, arsip, arsip_versi, kpi, kpi_realisasi, agenda, notifikasi, audit_log, app_settings), indeks, RLS + policy per peran, trigger `updated_at` & auto-profil, fungsi `my_app_role()`, 2 bucket storage, seed data (30 pegawai + arsip + KPI + agenda) + **8 akun demo otomatis**. Terverifikasi tereksekusi bersih & idempoten (aman dijalankan ulang) |
| `supabase/functions/gemini-proxy/index.ts` | Edge Function Deno **v2.2** — menjembatani Gemini API tanpa mengekspos API key; kode kesalahan berkode + action `diag` (diagnosa model) |
| `PANDUAN-INSTALASI.md` | Panduan instalasi lengkap (lokal, Supabase, Gemini, RBAC, FAQ + solusi ERROR 42P01, kesalahan Gemini berkode) |

## Start Cepat

1. **Mode demo (tanpa server):** buka `SMART-HRD.html` → klik salah satu akun demo di layar login (sandi per akun tampil di tombolnya, mis. `admin123`) → Masuk.
2. **Produksi:** buat project di supabase.com → SQL Editor → tempel **seluruh** `supabase-schema.sql` → Run → salin Project URL & anon key → Pengaturan → Koneksi Supabase → Simpan & Uji → login akun Supabase (sandi demo: `Madani2026`).
3. **Gemini (opsional):** Pengaturan → Mesin AI → pilih model **Gemini 3.8 Flash** ⭐ (atau 2.5 Pro/Flash, 2.0 Flash, model kustom) → isi API key, atau deploy `gemini-proxy` (mode aman, secret `GEMINI_API_KEY`).

## 8 Akun Demo

**Mode Lokal** (sandi per akun): `admin@madani.sch.id`/`admin123` · `manajer@madani.sch.id`/`manajer123` · `kabid@madani.sch.id`/`kabid123` · `kepegawaian@madani.sch.id`/`staf123` · `kinerja@madani.sch.id`/`kinerja123` · `direktur@madani.sch.id`/`direktur123` · `kepsek@madani.sch.id`/`kepsek123` · `pegawai@madani.sch.id`/`pegawai123`

**Mode Supabase** (8 akun dibuat otomatis oleh bagian 8 skrip, sandi seragam): `Madani2026`

## Fitur Utama

- **Dashboard**: 16 statistik kepegawaian, 5 grafik (tren rekrutmen, komposisi status, pegawai/unit, dokumen/jenis, capaian KPI), kalender kegiatan, antrean persetujuan.
- **10 Modul**: Surat Otomatis (32 jenis — termasuk PKWT, PKWTT, SP1–SP3, SK, surat keterangan kerja/penghasilan, perpanjangan kontrak, berita acara), SOP Generator (20 bagian + diagram alur + analisis risiko + perbandingan versi), Job Description (20 bagian, 5 jenjang), Instruksi Kerja (15 bagian), Pedoman (17 jenis), Kebijakan & Regulasi (11 jenis — Peraturan Kepegawaian & Tata Tertib), MADANI HR Assistant (chat + lampiran PDF/DOCX/XLSX), Database Pegawai (CRUD + import/export Excel + profil + riwayat), Manajemen Kinerja (KPI SMART, kaskade L1–L3, realisasi, evaluasi triwulan/semester/tahunan), DMS (11 kategori arsip, **opsi ✏️ Edit semua peran berwenang + 📝 Usulan Perubahan untuk Pegawai**, versi dokumen otomatis dengan uraian perubahan, riwayat versi, pengingat kedaluwarsa).
- **AI Hybrid**: generator lokal 100% tanpa API key + Gemini opsional (8 kemampuan AI surat, 10 AI Tools: Document Checker, Translator, Summarizer, Organizational Analyzer, Workload Analyzer, HR Report Generator, Letter Response, Legal Review, Form Generator, Checklist Generator).
- **Tata kelola**: workflow 7 tahap, 8 status dokumen, riwayat persetujuan & versi, RBAC 8 peran, audit log, RLS Supabase, AI dilarang mengarang dasar hukum (penanda [WAJIB VERIFIKASI]).
- **Standar dokumen**: bahasa Indonesia formal, penomoran otomatis `NNN/JENIS/KODE/BLN/TAHUN`, kop lembaga, bagian pengesahan, siap cetak PDF / ekspor DOCX / Excel.
- **Penyimpanan konfigurasi AI**: API key Gemini otomatis tersimpan di perangkat (slot khusus) + tersinkron ke tabel `app_settings` untuk Admin Sistem & Manajer HRD — login ulang tanpa mengisi ulang kunci.

## Riwayat Pembaruan

| Versi | Tanggal | Perubahan |
|---|---|---|
| v1.1 | 4 Nov 2026 | API key Gemini tersimpan otomatis (tidak hilang saat logout/login); Edge Function v2.2 (dukungan Gemini 3.x, pesan kesalahan berkode, tombol Diagnosa); Panduan diperbarui |
| v1.0 | 3 Nov 2026 | Rilis awal paket (aplikasi + skema SQL v2.1 + Edge Function + panduan) |
