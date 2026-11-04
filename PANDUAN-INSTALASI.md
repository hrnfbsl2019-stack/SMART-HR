# 📘 PANDUAN INSTALASI — SMART HRD v1.0 (Skrip SQL v2.1 · Edge Function v2.2)
**AI Powered Personnel Administration System · Yayasan Pendidikan Madani**

---

## 1. Isi Paket

| File | Fungsi |
|---|---|
| `SMART-HRD.html` | Aplikasi lengkap (1 file) — 10 modul, dashboard 16 statistik + 5 grafik, workflow persetujuan 7 tahap, 8 fitur AI tambahan, MADANI HR Assistant, **Edit + Riwayat Versi di Arsip Dokumen** |
| ↳ *pembaruan terbaru* | **📋 Unduh Template Pegawai** (template Excel + sheet Petunjuk), **paginasi tabel pegawai** (10/15/25/50/Semua), **draf isian AI muncul otomatis** di semua modul produksi dokumen (muncul seketika, ditingkatkan versi AI di latar belakang), **✍️ Edit Manual & ✏️ Edit Isi** pada seluruh daftar surat/dokumen (semua status — setiap simpanan menjadi versi baru, dokumen terbit yang direvisi otomatis kembali ke Draft untuk pengajuan ulang) |
| `supabase-schema.sql` | **Kode SQL lengkap untuk Supabase SQL Editor (v2.1 — urutan diperbaiki)**: 12 tabel, indeks, trigger, RLS/policy per peran, 2 bucket storage, seed data (30 pegawai + dokumen + KPI + agenda), dan **8 akun demo otomatis** |
| `supabase/functions/gemini-proxy/index.ts` | Edge Function untuk memanggil Gemini **tanpa** mengekspos API key ke browser |
| `PANDUAN-INSTALASI.md` | Dokumen ini |

---

## 2. Mode Cepat (Tanpa Server) — 2 Menit

1. Buka `SMART-HRD.html` di browser (Chrome/Edge/Firefox).
2. Aplikasi langsung jalan di **Mode Lokal (Demo)** — data tersimpan di localStorage peramban.
3. Klik salah satu **8 akun demo** di layar login (sandi per akun tampil di tombolnya, mis. `admin123` / `manajer123`), lalu **Masuk**.
4. Ganti identitas lembaga di **Pengaturan → Identitas Lembaga** (otomatis mengubah kop surat).

> Mode lokal mencakup SEMUA fitur: generator dokumen AI hybrid, workflow 7 tahap, kinerja KPI, DMS dengan edit + versi, AI tools, dan asisten chat.

---

## 3. Koneksi Supabase (Produksi) — 10 Menit

### 3.1 Buat project & jalankan SQL
1. Daftar/masuk di [supabase.com](https://supabase.com) → **New project** (pilih region terdekat, mis. Singapore).
2. Buka **SQL Editor → New query**.
3. Buka file `supabase-schema.sql`, **salin SELURUH isinya** (Ctrl+A → Ctrl+C), tempel di SQL Editor → klik **Run**. Jalankan **sekali utuh** — jangan dipotong-potong.
4. Yang terpasang otomatis:
   - Tabel: `profiles, pegawai, surat, dokumen, arsip, arsip_versi, kpi, kpi_realisasi, agenda, notifikasi, audit_log, app_settings`
   - Indeks, trigger `updated_at`, trigger auto-profil saat user baru mendaftar (`handle_new_user`).
   - Fungsi keamanan `my_app_role()` (dibuat **setelah** tabel — perbaikan v2.1).
   - **RLS aktif di semua tabel** dengan policy per peran (RBAC di tingkat database).
   - Bucket storage: `dokumen` (privat) dan `avatar` (publik).
   - Seed data: profil lembaga, **30 pegawai**, 5 surat contoh, 6 dokumen, 11 arsip + 5 riwayat versi, 6 KPI + 18 realisasi (kaskade Direktur → Unit → Individu), 4 agenda, notifikasi, audit log.
   - **8 akun demo** di Authentication (bagian 8) — password seragam: **`Madani2026`**.

### 3.2 Akun demo (dibuat otomatis oleh bagian 8 skrip)

| Email | Peran |
|---|---|
| `admin@madani.sch.id` | Admin Sistem |
| `manajer@madani.sch.id` | Manajer HRD |
| `kabid@madani.sch.id` | Kepala Bidang HRD |
| `kepegawaian@madani.sch.id` | Staf Kepegawaian |
| `kinerja@madani.sch.id` | Staf Kinerja & Pengembangan SDM |
| `direktur@madani.sch.id` | Direktur |
| `kepsek@madani.sch.id` | Kepala Unit/Sekolah |
| `pegawai@madani.sch.id` | Pegawai |

> Jika kebijakan proyek Anda melarang insert ke `auth.users`, blok bagian 8 **terlewati dengan aman** — buat user manual di **Authentication → Users → Add user** (centang *Auto Confirm User*), lalu **jalankan ulang skrip** agar profil & role terisi otomatis.

### 3.3 Hubungkan aplikasi
1. Di Supabase: **Settings → API** → salin **Project URL** dan **anon public** key.
2. Di aplikasi: **Pengaturan → Koneksi Supabase** → tempel keduanya → **Simpan & Uji Koneksi**.
3. **Keluar**, lalu login memakai akun Supabase, mis. `admin@madani.sch.id` / `Madani2026`.

> Amankan anon key? Ya — key anon boleh publik karena **RLS membatasi akses per baris**. Service key TIDAK boleh masuk frontend.

---

## 4. Aktifkan Gemini AI (Opsional) — 5 Menit

**Model yang tersedia di aplikasi:** **Gemini 3.8 Flash** ⭐ (pilihan utama — ID resmi Google), Gemini 3.6 Flash, Gemini 3.5 Flash-Lite, Gemini 3.1 Pro, Gemini 2.5 Pro/Flash, Gemini 2.0 Flash, + isian model kustom.

Ambil API key gratis di [Google AI Studio](https://aistudio.google.com/apikey), lalu pilih salah satu **Rute Panggilan AI** di Pengaturan → Mesin AI (Gemini):

> **Format kunci:** AI Studio kini menerbitkan kunci baru berawalan **`AQ.`** (*Authentication Key*, mis. `AQ.Ab8…`) sebagai pengganti format lama `AIza…`. Ini format resmi dan **didukung penuh aplikasi pada kedua rute** — rute browser memakai parameter `?key=` dan rute Edge Function memakai header `x-goog-api-key`, keduanya diterima API native Gemini. (Catatan: kunci `AIza` lama sudah ditolak API Gemini sejak September 2026.)

**A. Rute langsung dari browser (praktis)**
- Rute Panggilan AI → **"Langsung dari browser"** → tempel API key → pilih model → **Simpan Konfigurasi AI** → **Uji Gemini Sekarang**.
- Key disimpan hanya di localStorage peramban Anda.

**B. Rute Via Supabase Edge Function (disarankan — kunci tidak pernah menyentuh browser)**
```bash
npm install -g supabase          # bila belum ada
supabase login
supabase link --project-ref <PROJECT_REF>
supabase functions deploy gemini-proxy
supabase secrets set GEMINI_API_KEY=AQ.Ab8...    # opsional — lihat catatan di bawah
# opsional: supabase secrets set ALLOWED_ORIGINS=https://domain-anda
```
Atau tanpa CLI: **Supabase Dashboard → Edge Functions → Create a new function** → beri nama `gemini-proxy` → tempel seluruh isi `supabase/functions/gemini-proxy/index.ts` → **Deploy** → buka tab **Secrets** → tambah `GEMINI_API_KEY`.

> ⚠️ **SUDAH PERNAH DEPLOY SEBELUMNYA? WAJIB DEPLOY ULANG (Function v2.2).** Versi function lama masih mengirim parameter `temperature` yang kini **ditolak Google** untuk semua model Gemini 3.x ke atas (Gemini 3.5/3.6/3.7/3.8 Flash, 4.x) — penyebab paling umum pesan *“Gemini menolak permintaan.”* Buka **Edge Functions → gemini-proxy → Edit → kosongkan editor, tempel ulang seluruh isi file terbaru → Deploy**. Versi 2.2 juga menambahkan: pesan kesalahan yang menyebut **penyebab persisnya** (kunci tidak valid / model tidak dikenal / kuota), dan action `diag` untuk tombol **🔍 Diagnosa Kunci & Model** di aplikasi.

Lalu di aplikasi: **Pengaturan → Mesin AI → Rute Panggilan AI → "Via Supabase Edge Function" → Simpan Konfigurasi AI** → klik **⚡ Uji Gemini Sekarang**. Bila gagal, klik **🔍 Diagnosa Kunci & Model** — tombol ini menghubungi server dan menampilkan: (1) apakah kunci Anda **valid** menurut Google, (2) **daftar model yang benar-benar tersedia** untuk kunci tersebut lengkap dengan tombol **Pakai** untuk memilihnya sekali klik.

> **Dua sumber kunci di server:** Edge Function membaca secret `GEMINI_API_KEY` lebih dulu; bila secret tidak di-set, ia otomatis memakai kunci yang Admin/Manajer HRD tempel di kolom API key aplikasi (tersimpan di tabel `app_settings`, dilindungi RLS — tidak pernah terkirim kembali ke browser). Setiap panggilan AI tercatat di **Audit Log** (`AI_CALL`) dan dibatasi 30 permintaan/menit per pengguna.

> **Arsitektur Hybrid:** tanpa API key, seluruh generator dokumen tetap berfungsi 100% (template resmi lokal). Dengan Gemini aktif, fitur perbaikan bahasa, edit naratif, terjemahan, ringkasan, letter response, dan chat assistant naik kelas ke LLM.

---

## 5. Peta Menu & Hak Akses (RBAC 8 Peran)

| Modul | Pegawai | Kepala Unit | Staf HRD | Kabid | Manajer | Direktur | Admin |
|---|---|---|---|---|---|---|---|
| Dashboard | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Database Pegawai | lihat | lihat/unit | kelola | kelola | kelola | lihat | kelola |
| Pusat Persetujuan | — | tahap 6 | tahap 2–3 | tahap 3 | tahap 4 | tahap 6 | terbitkan (7) |
| Surat/SOP/IK/JD/Pedoman/Regulasi | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Manajemen Kinerja | lihat | ✔ | kelola | kelola | kelola | ✔ | ✔ |
| **Arsip Dokumen — Edit** | usulan (📝) | ✔ edit | ✔ edit | ✔ edit | ✔ edit | ✔ edit | ✔ edit |
| DMS & AI Tools | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Audit Log | — | — | — | — | ✔ | — | ✔ |
| Pengaturan | — | — | — | — | ✔ | — | ✔ |

> **Edit Arsip Dokumen:** setiap dokumen punya tombol ✏️ **Edit** — perubahan metadata/isi/lampiran tersimpan sebagai **versi baru** otomatis, tercatat di **Riwayat Versi** (🕘) dan **Audit Log**. Peran Pegawai mengirim 📝 **Usulan Perubahan** yang diteruskan ke Manajer HRD & Admin Sistem.

---

## 6. Alur Kerja Harian yang Disarankan

1. **Rekrutmen:** AI Tools → Checklist Penerimaan Pegawai Baru → SK Pengangkatan Percobaan (Surat Otomatis) → ajukan 7 tahap → terbit.
2. **Kontrak:** Dashboard menampilkan pengingat kontrak ≤90 hari → Surat Perpanjangan Kontrak / PKWT baru → tandatangani (cetak + meterai) → arsip DMS kategori *Perjanjian Kerja*.
3. **Kedisiplinan:** Surat Panggilan → Berita Acara Pembinaan → SP1/SP2/SP3 sesuai jenjang Tata Tertib.
4. **Kinerja:** tetapkan KPI L1/L2/L3 (kaskade) → input realisasi tiap triwulan → Evaluasi Periodik → cetak laporan.
5. **Revisi dokumen:** buka Arsip Dokumen → ✏️ Edit → isi *Uraian Perubahan* → simpan → versi baru + riwayat tersedia; usulan dari pegawai ditinjau lewat detail arsip.
6. **Dokumen legal:** semua perjanjian (PKWT/PKWTT) dan regulasi (Peraturan Kepegawaian, Tata Tertib) lolos **Legal Review** (AI Tools) sebelum disahkan.

---

## 7. Pemecahan Masalah (FAQ)

| Gejala | Solusi |
|---|---|
| **`ERROR 42P01: relation "public.profiles" does not exist`** | Anda memakai skrip versi lama yang membuat fungsi sebelum tabel, atau menjalankan skrip **sebagian**. Gunakan `supabase-schema.sql` **v2.1**, salin **seluruh** isi, klik **Run** sekali utuh. Skrip v2.1 sudah diverifikasi tereksekusi bersih dan aman diulang. |
| Skrip gagal di tengah lalu ingin mengulang | Tidak perlu hapus apa pun — skrip v2.1 **idempoten**; jalankan ulang seluruh isinya. |
| "Koneksi gagal" saat uji Supabase | Pastikan `supabase-schema.sql` sudah di-Run di project yang sama; cek URL diakhiri `.supabase.co` tanpa garis miring. |
| Login Supabase gagal "Invalid login credentials" | Jalankan ulang skema (bagian 8 membuat akun demo; idempoten). Sandi: `Madani2026`. Bila tetap gagal, buat user manual di Authentication lalu jalankan ulang skrip. |
| Gemini "API key invalid" | Buat ulang key di AI Studio; atau gunakan rute Edge Function dan cek `supabase secrets list`. |
| **“Gemini menolak permintaan.”** (function versi lama) | Pesan lama yang menyembunyikan penyebab. Penyebab paling sering: **parameter `temperature` ditolak model Gemini 3.x** (sudah diperbaiki di Function v2.2 → **deploy ulang**), kunci tidak valid, atau model tidak dikenal. Setelah deploy ulang, pesan akan menyebut penyebab persisnya — dan tombol **🔍 Diagnosa Kunci & Model** memperlihatkan daftar model yang valid untuk kunci Anda. |
| **“Model … tidak dikenal Google” (`MODEL_UNKNOWN`)** | ID model tidak tersedia untuk kunci/akun Anda (mis. model preview butuh izin). Jalankan **🔍 Diagnosa** lalu klik **Pakai** pada salah satu model yang muncul (pilihan aman: `gemini-3.8-flash`, `gemini-3.6-flash`, atau `gemini-2.0-flash`). |
| **“Kunci API DITOLAK Google” (`BAD_KEY`)** | Kunci salah salin / belum aktif: salin ulang **utuh** dari AI Studio (awalan `AQ.` atau `AIza`, tanpa spasi), tunggu 1–5 menit setelah pembuatan, lalu **Simpan** dan ulangi Diagnosa. |
| **“Kuota/batas pemakaian tercapai” (`QUOTA`)** | Kuota free-tier habis atau model belum aktif untuk akun free — tunggu sebentar, ganti model lebih ringan (3.5 Flash-Lite / 2.0 Flash), atau aktifkan billing. |
| **“Wilayah jaringan belum didukung” (`REGION`)** | Rute browser memakai jaringan yang diblokir Google — pindah ke rute **Via Supabase Edge Function** (panggilan dari server Supabase), atau ganti jaringan. |
| "Tidak dapat menghubungi Edge Function gemini-proxy" | Function belum dideploy di project Supabase yang sama — ikuti langkah **4.B**; pastikan nama function persis `gemini-proxy`. |
| "Kunci API Gemini belum tersedia di server" (kode `NO_API_KEY`) | Tempel API key di Pengaturan → Mesin AI lalu **Simpan** (Admin/Manajer HRD), atau jalankan `supabase secrets set GEMINI_API_KEY=AQ.Ab8...`. |
| Respons **429 "ResourceExhausted (limit: 0)"** | Kuota akun free-tier Anda belum aktif untuk model tersebut — tunggu beberapa menit, coba model lain (mis. Gemini 3.6 Flash), atau aktifkan billing di AI Studio. Ini batasan akun Google, bukan bug aplikasi. |
| Edge Function balas 401/403 | Pengguna wajib login Supabase (bukan mode lokal) dan profilnya ada di tabel `profiles` — login ulang dengan akun demo. |
| **API key Gemini hilang setiap kali logout/login** | Sudah diperbaiki di aplikasi terbaru: kunci AI kini disimpan **otomatis** di penyimpanan khusus (localStorage `smarthrd_gm`, pola sama seperti koneksi Supabase) sehingga tidak terpengaruh penuhnya kuota data, dan kunci kosong dari server **tidak pernah** menimpa kunci yang valid. Untuk Admin/Manajer HRD yang terhubung Supabase, kunci juga tersinkron ke tabel `app_settings` — pindah perangkat pun terisi otomatis. Cukup tempel kunci **satu kali** lalu **Simpan**. |
| Popup cetak tidak muncul | Izinkan popup untuk situs ini (ikon di address bar). |
| Ingin reset data demo | Mode lokal: hapus localStorage situs ini. Supabase: hapus isi tabel `pegawai, surat, dokumen, arsip, kpi, agenda, notifikasi` lalu jalankan ulang skrip. |

---

## 8. Catatan Keamanan

- Kata sandi demo hanya untuk uji coba — **ganti segera** lewat Supabase Dashboard → Authentication → Users.
- AI **tidak mengarang dasar hukum**: rujukan eksternal dihasilkan apa adanya dari input penyusun dan ditandai **[WAJIB VERIFIKASI]**.
- Semua aktivitas penting tercatat di **Audit Log** (login/logout, tambah/ubah/hapus pegawai, edit arsip + versi, KPI, persetujuan, cetak, ekspor).
- Kunci API Gemini yang disimpan server-side (tabel `app_settings`) hanya dapat dibaca peran **Admin Sistem** dan **Manajer HRD** (dijaga RLS).
- Data gaji hanya tampil bagi peran HRD & Direktur.
