-- ============================================================================
-- SMART HRD — AI POWERED PERSONNEL ADMINISTRATION SYSTEM
-- SKRIP SQL LENGKAP UNTUK SUPABASE SQL EDITOR  (v2.1 — URUTAN DIPERBAIKI)
-- Yayasan Pendidikan Madani
-- ----------------------------------------------------------------------------
-- PERBAIKAN v2.1 (mengatasi error Anda):
--   ERROR: 42P01: relation "public.profiles" does not exist  (LINE 24)
--   Penyebab : fungsi my_app_role() (LANGUAGE SQL) dibuat SEBELUM tabel
--              profiles. PostgreSQL memvalidasi isi fungsi SQL saat dibuat,
--              sehingga tabel yang dirujuk WAJIB sudah ada lebih dulu.
--   Solusi   : urutan skrip diatur ulang → TABEL DIBUAT DULU, baru FUNGSI,
--              lalu TRIGGER, RLS/POLICY, STORAGE, dan DATA AWAL.
-- ----------------------------------------------------------------------------
-- CARA PAKAI:
--   1. Buka dashboard proyek Supabase Anda  (https://supabase.com/dashboard)
--   2. Menu kiri:  SQL Editor  ->  New query
--   3. SALIN SELURUH isi file ini (Ctrl+A → Ctrl+C), TEMPEL, lalu klik  RUN
--      (jalankan SEKALI UTUH dari atas sampai bawah — jangan dipotong-potong).
--   4. Aman dijalankan ulang (idempoten): objek yang sudah ada tidak dibuat
--      ulang dan data yang sudah ada tidak ditimpa.
--   5. Ambil Project URL & anon key di: Project Settings -> API
--      lalu tempel di aplikasi SMART HRD -> menu Pengaturan -> Koneksi Supabase.
-- ----------------------------------------------------------------------------
-- AKUN DEMO: 8 akun login dibuat otomatis di bagian 8 (password: Madani2026).
-- Jika pembuatan otomatis gagal di lingkungan Anda, buat user manual lewat
-- Authentication -> Users -> Add user, lalu jalankan ulang skrip ini.
-- ============================================================================

-- 0. EKSTENSI ----------------------------------------------------------------
create extension if not exists pgcrypto;

-- 1. FUNGSI BANTU (plpgsql — aman dibuat sebelum tabel; fungsi my_app_role
--    dipindah ke bagian 2.12 SETELAH tabel profiles, lihat catatan v2.1) ------

-- Otomatis mengisi kolom updated_at saat UPDATE
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Saat ada user baru mendaftar di Supabase Auth, buat otomatis profilnya
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, nama, role, aktif)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nama', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'role', 'pegawai'),
    true
  )
  on conflict (email) do update set id = excluded.id, updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2. TABEL UTAMA ---------------------------------------------------------------
-- 2.1 profiles — pengguna sistem (8 role)
create table if not exists public.profiles (
  id          uuid primary key default gen_random_uuid(),
  email       text unique not null,
  nama        text not null,
  role        text not null check (role in (
                'admin_sistem','manajer_hrd','kepala_bidang','staf_kepegawaian',
                'staf_kinerja','direktur','kepala_unit','pegawai')),
  unit        text,
  jabatan     text,
  telepon     text,
  aktif       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2.2 pegawai — database kepegawaian
create table if not exists public.pegawai (
  id            text primary key,
  nip           text unique,
  nama          text not null,
  jk            text check (jk in ('L','P')),
  tempat_lahir  text,
  tgl_lahir     date,
  pendidikan    text,
  jabatan       text,
  unit          text,
  jenis_pegawai text check (jenis_pegawai in
                ('PNS','PPPK','Guru Tetap','Guru Tidak Tetap','Tenaga Kekaryaan','Karyawan Harian')),
  tgl_masuk     date,
  status        text not null default 'Aktif' check (status in ('Aktif','Cuti','Izin','Suspend','Keluar')),
  kontrak_sampai date,
  gaji_pokok    numeric default 0,
  email         text,
  telepon       text,
  alamat        text,
  payload       jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- 2.3 surat — arsip surat & dokumen legal yang dihasilkan Modul 1
create table if not exists public.surat (
  id          text primary key,
  jenis       text not null,
  nomor       text,
  perihal     text,
  penerima    text,
  status      text not null default 'Draft',
  tahap       int not null default 1,
  tanggal     date,
  created_by  text,
  payload     jsonb not null default '{}'::jsonb,   -- isi html, params, riwayat edit
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2.4 dokumen — SOP / IK / Deskripsi Jabatan / Pedoman / Kebijakan (Modul 2-6)
create table if not exists public.dokumen (
  id          text primary key,
  kategori    text not null check (kategori in
              ('SOP','Instruksi Kerja','Deskripsi Jabatan','Pedoman','Kebijakan & Regulasi')),
  judul       text not null,
  nomor       text,
  versi       int not null default 1,
  status      text not null default 'Draft',
  tahap       int not null default 1,
  tanggal     date,
  kedaluwarsa date,
  created_by  text,
  payload     jsonb not null default '{}'::jsonb,   -- konten html, params, riwayat versi
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2.5 arsip — Document Management System (Modul 10, mendukung EDIT + versi)
create table if not exists public.arsip (
  id               text primary key,
  judul            text not null,
  kategori         text not null check (kategori in (
                     'Surat Keputusan (SK)','Surat Menyurat','SOP','Instruksi Kerja',
                     'Deskripsi Jabatan','Pedoman','Kebijakan & Regulasi','Perjanjian Kerja',
                     'Laporan Kinerja','Berita Acara','Dokumen Lainnya')),
  nomor            text,
  tanggal_dokumen  date,
  unit             text,
  pic              text,
  kerahasiaan      text not null default 'Internal' check (kerahasiaan in
                     ('Publik','Internal','Rahasia','Sangat Rahasia')),
  status           text not null default 'Aktif' check (status in ('Aktif','Diarsipkan','Kedaluwarsa')),
  deskripsi        text,
  kedaluwarsa      date,
  versi            int not null default 1,
  file_name        text,
  file_size        bigint,
  file_url         text,
  created_by       text,
  payload          jsonb not null default '{}'::jsonb,  -- dataURL file lokal, tags
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- 2.6 arsip_versi — riwayat versi arsip (otomatis saat tombol EDIT dipakai)
create table if not exists public.arsip_versi (
  id           text primary key,
  arsip_id     text not null references public.arsip(id) on delete cascade,
  versi        int not null,
  diubah_oleh  text,
  perubahan    text,
  snapshot     jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);

-- 2.7 kpi + realisasi — Manajemen Kinerja (Modul 9, KPI SMART & cascading)
create table if not exists public.kpi (
  id          text primary key,
  nama        text not null,
  deskripsi   text,
  level       text not null check (level in ('Direktur','Unit','Individu')),
  parent_kpi  text references public.kpi(id) on delete set null,
  unit        text,
  pic         text,
  target      numeric not null default 100,
  satuan      text default '%',
  baseline    numeric,
  periode     text,
  batas_waktu date,
  payload     jsonb not null default '{}'::jsonb,   -- rincian SMART, evaluasi berkala
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.kpi_realisasi (
  id           text primary key,
  kpi_id       text not null references public.kpi(id) on delete cascade,
  periode      text not null,          -- TW-1 .. TW-4
  realisasi    numeric not null default 0,
  catatan      text,
  dinilai_oleh text,
  payload      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- 2.8 agenda — jadwal kegiatan HRD
create table if not exists public.agenda (
  id         text primary key,
  judul      text not null,
  tanggal    date not null,
  waktu      text,
  tempat     text,
  peserta    text,
  keterangan text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2.9 notifikasi
create table if not exists public.notifikasi (
  id         text primary key,
  user_email text,                -- null = semua
  target_role text,               -- null = semua
  judul      text not null,
  pesan      text,
  tipe       text default 'info', -- info / peringatan / sukses
  dibaca     boolean not null default false,
  created_at timestamptz not null default now()
);

-- 2.10 audit_log — jejak audit seluruh aktivitas
create table if not exists public.audit_log (
  id         text primary key,
  user_email text,
  user_role  text,
  aksi       text not null,       -- LOGIN / CREATE / UPDATE / DELETE / APPROVE / PRINT / EXPORT ...
  entitas    text,                -- pegawai / surat / dokumen / arsip / kpi / pengaturan
  entitas_id text,
  detail     text,
  created_at timestamptz not null default now()
);

-- 2.11 app_settings — profil lembaga + konfigurasi AI (API key TIDAK terekspos
--      ke role lain karena RLS di bawah; disimpan server-side)
create table if not exists public.app_settings (
  id         text primary key default 'global',
  lembaga    jsonb not null default '{}'::jsonb,
  gemini     jsonb not null default '{}'::jsonb,
  updated_by text,
  updated_at timestamptz not null default now()
);

-- 2.12 FUNGSI ROLE (DIBUAT SETELAH TABEL PROFILES — perbaikan error 42P01) ------
-- Mengambil role pengguna saat ini dari tabel profiles (berdasarkan email JWT).
-- SECURITY DEFINER → aman dari rekursi RLS pada tabel profiles itu sendiri.
create or replace function public.my_app_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles
  where lower(email) = lower(coalesce(auth.jwt()->>'email',''))
  limit 1;
$$;

-- 3. INDEKS --------------------------------------------------------------------
create index if not exists idx_pegawai_unit      on public.pegawai(unit);
create index if not exists idx_pegawai_status    on public.pegawai(status);
create index if not exists idx_pegawai_jenis     on public.pegawai(jenis_pegawai);
create index if not exists idx_surat_status      on public.surat(status);
create index if not exists idx_surat_jenis       on public.surat(jenis);
create index if not exists idx_dokumen_kategori  on public.dokumen(kategori);
create index if not exists idx_dokumen_status    on public.dokumen(status);
create index if not exists idx_arsip_kategori    on public.arsip(kategori);
create index if not exists idx_arsip_kedaluwarsa on public.arsip(kedaluwarsa);
create index if not exists idx_arsip_versi_arsip on public.arsip_versi(arsip_id);
create index if not exists idx_kpi_unit          on public.kpi(unit);
create index if not exists idx_realisasi_kpi     on public.kpi_realisasi(kpi_id);
create index if not exists idx_audit_created     on public.audit_log(created_at desc);
create index if not exists idx_notif_email       on public.notifikasi(user_email);

-- 4. TRIGGER updated_at ----------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['profiles','pegawai','surat','dokumen','arsip','kpi',
                           'kpi_realisasi','agenda','app_settings'] loop
    execute format('drop trigger if exists trg_%1$s_updated on public.%1$s;
      create trigger trg_%1$s_updated before update on public.%1$s
      for each row execute function public.handle_updated_at();', t);
  end loop;
end $$;

-- 5. ROW LEVEL SECURITY (RBAC DI TINGKAT DATABASE) -------------------------------
alter table public.profiles      enable row level security;
alter table public.pegawai       enable row level security;
alter table public.surat         enable row level security;
alter table public.dokumen       enable row level security;
alter table public.arsip         enable row level security;
alter table public.arsip_versi   enable row level security;
alter table public.kpi           enable row level security;
alter table public.kpi_realisasi enable row level security;
alter table public.agenda        enable row level security;
alter table public.notifikasi    enable row level security;
alter table public.audit_log     enable row level security;
alter table public.app_settings  enable row level security;

-- 5.1 profiles
drop policy if exists p_profiles_sel on public.profiles;
create policy p_profiles_sel on public.profiles for select to authenticated
  using (lower(email)=lower(coalesce(auth.jwt()->>'email',''))
         or public.my_app_role() in ('admin_sistem','manajer_hrd','kepala_bidang','direktur'));
drop policy if exists p_profiles_ins on public.profiles;
create policy p_profiles_ins on public.profiles for insert to authenticated
  with check (public.my_app_role()='admin_sistem');
drop policy if exists p_profiles_upd on public.profiles;
create policy p_profiles_upd on public.profiles for update to authenticated
  using (lower(email)=lower(coalesce(auth.jwt()->>'email','')) or public.my_app_role()='admin_sistem');
drop policy if exists p_profiles_del on public.profiles;
create policy p_profiles_del on public.profiles for delete to authenticated
  using (public.my_app_role()='admin_sistem');

-- 5.2 pegawai — baca semua login; tulis HRD & admin; hapus admin/manajer
drop policy if exists p_pegawai_sel on public.pegawai;
create policy p_pegawai_sel on public.pegawai for select to authenticated using (true);
drop policy if exists p_pegawai_ins on public.pegawai;
create policy p_pegawai_ins on public.pegawai for insert to authenticated
  with check (public.my_app_role() in ('admin_sistem','manajer_hrd','staf_kepegawaian'));
drop policy if exists p_pegawai_upd on public.pegawai;
create policy p_pegawai_upd on public.pegawai for update to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd','staf_kepegawaian'));
drop policy if exists p_pegawai_del on public.pegawai;
create policy p_pegawai_del on public.pegawai for delete to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd'));

-- 5.3 surat — semua login boleh membuat draf; persetujuan sesuai alur
drop policy if exists p_surat_sel on public.surat;
create policy p_surat_sel on public.surat for select to authenticated using (true);
drop policy if exists p_surat_ins on public.surat;
create policy p_surat_ins on public.surat for insert to authenticated with check (true);
drop policy if exists p_surat_upd on public.surat;
create policy p_surat_upd on public.surat for update to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd','kepala_bidang','staf_kepegawaian','staf_kinerja','direktur','kepala_unit')
         or created_by = auth.jwt()->>'email');
drop policy if exists p_surat_del on public.surat;
create policy p_surat_del on public.surat for delete to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd') or created_by = auth.jwt()->>'email');

-- 5.4 dokumen (SOP/IK/JD/Pedoman/Kebijakan)
drop policy if exists p_dok_sel on public.dokumen;
create policy p_dok_sel on public.dokumen for select to authenticated using (true);
drop policy if exists p_dok_ins on public.dokumen;
create policy p_dok_ins on public.dokumen for insert to authenticated with check (true);
drop policy if exists p_dok_upd on public.dokumen;
create policy p_dok_upd on public.dokumen for update to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd','kepala_bidang','staf_kepegawaian','staf_kinerja','direktur','kepala_unit')
         or created_by = auth.jwt()->>'email');
drop policy if exists p_dok_del on public.dokumen;
create policy p_dok_del on public.dokumen for delete to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd') or created_by = auth.jwt()->>'email');

-- 5.5 arsip — SEMUA login bisa membaca & MENGEDIT (tombol Edit di aplikasi)
drop policy if exists p_arsip_sel on public.arsip;
create policy p_arsip_sel on public.arsip for select to authenticated using (true);
drop policy if exists p_arsip_ins on public.arsip;
create policy p_arsip_ins on public.arsip for insert to authenticated with check (true);
drop policy if exists p_arsip_upd on public.arsip;
create policy p_arsip_upd on public.arsip for update to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd','kepala_bidang','staf_kepegawaian','staf_kinerja','direktur','kepala_unit')
         or created_by = auth.jwt()->>'email');
drop policy if exists p_arsip_del on public.arsip;
create policy p_arsip_del on public.arsip for delete to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd') or created_by = auth.jwt()->>'email');

-- 5.6 arsip_versi — riwayat tidak boleh diubah/dihapus (jejak audit versi)
drop policy if exists p_aver_sel on public.arsip_versi;
create policy p_aver_sel on public.arsip_versi for select to authenticated using (true);
drop policy if exists p_aver_ins on public.arsip_versi;
create policy p_aver_ins on public.arsip_versi for insert to authenticated with check (true);

-- 5.7 kpi & realisasi
drop policy if exists p_kpi_sel on public.kpi;
create policy p_kpi_sel on public.kpi for select to authenticated using (true);
drop policy if exists p_kpi_ins on public.kpi;
create policy p_kpi_ins on public.kpi for insert to authenticated with check (true);
drop policy if exists p_kpi_upd on public.kpi;
create policy p_kpi_upd on public.kpi for update to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd','staf_kinerja','direktur','kepala_bidang','kepala_unit'));
drop policy if exists p_kpi_del on public.kpi;
create policy p_kpi_del on public.kpi for delete to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd','staf_kinerja'));

drop policy if exists p_real_sel on public.kpi_realisasi;
create policy p_real_sel on public.kpi_realisasi for select to authenticated using (true);
drop policy if exists p_real_ins on public.kpi_realisasi;
create policy p_real_ins on public.kpi_realisasi for insert to authenticated with check (true);
drop policy if exists p_real_upd on public.kpi_realisasi;
create policy p_real_upd on public.kpi_realisasi for update to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd','staf_kinerja','direktur','kepala_bidang','kepala_unit'));
drop policy if exists p_real_del on public.kpi_realisasi;
create policy p_real_del on public.kpi_realisasi for delete to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd','staf_kinerja'));

-- 5.8 agenda
drop policy if exists p_ag_sel on public.agenda;
create policy p_ag_sel on public.agenda for select to authenticated using (true);
drop policy if exists p_ag_ins on public.agenda;
create policy p_ag_ins on public.agenda for insert to authenticated with check (true);
drop policy if exists p_ag_upd on public.agenda;
create policy p_ag_upd on public.agenda for update to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd','staf_kepegawaian','kepala_unit'));
drop policy if exists p_ag_del on public.agenda;
create policy p_ag_del on public.agenda for delete to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd'));

-- 5.9 notifikasi — semua login membaca; menandai dibaca untuk dirinya
drop policy if exists p_notif_sel on public.notifikasi;
create policy p_notif_sel on public.notifikasi for select to authenticated using (true);
drop policy if exists p_notif_ins on public.notifikasi;
create policy p_notif_ins on public.notifikasi for insert to authenticated with check (true);
drop policy if exists p_notif_upd on public.notifikasi;
create policy p_notif_upd on public.notifikasi for update to authenticated using (true);

-- 5.10 audit_log — hanya admin & manajer yang boleh membaca; tidak bisa diedit
drop policy if exists p_audit_sel on public.audit_log;
create policy p_audit_sel on public.audit_log for select to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd'));
drop policy if exists p_audit_ins on public.audit_log;
create policy p_audit_ins on public.audit_log for insert to authenticated with check (true);

-- 5.11 app_settings — KUNCI API GEMINI hanya dapat dibaca Admin Sistem & Manajer HRD
--      (memenuhi persyaratan "API key tidak diekspos ke frontend umum")
drop policy if exists p_set_sel on public.app_settings;
create policy p_set_sel on public.app_settings for select to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd'));
drop policy if exists p_set_upd on public.app_settings;
create policy p_set_upd on public.app_settings for update to authenticated
  using (public.my_app_role() in ('admin_sistem','manajer_hrd'));

-- 6. STORAGE BUCKET ---------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('dokumen','dokumen', false), ('avatar','avatar', true)
on conflict (id) do nothing;

drop policy if exists "dokumen read" on storage.objects;
create policy "dokumen read" on storage.objects for select to authenticated
  using (bucket_id = 'dokumen');
drop policy if exists "dokumen insert" on storage.objects;
create policy "dokumen insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'dokumen');
drop policy if exists "dokumen update" on storage.objects;
create policy "dokumen update" on storage.objects for update to authenticated
  using (bucket_id = 'dokumen');
drop policy if exists "avatar read" on storage.objects;
create policy "avatar read" on storage.objects for select using (bucket_id = 'avatar');
drop policy if exists "avatar write" on storage.objects;
create policy "avatar write" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatar');

-- 7. DATA AWAL (SEED) --------------------------------------------------------------
-- 7.1 Profil lembaga default (bisa diubah di aplikasi: Pengaturan -> Profil Lembaga)
insert into public.app_settings (id, lembaga, gemini, updated_by) values (
 'global',
 '{"nama":"Yayasan Pendidikan Madani","singkatan":"YPM","alamat":"Jl. Pendidikan Raya No. 45, Kebayoran Baru, Jakarta Selatan 12190","telepon":"(021) 725-8845","email":"hrd@madani.sch.id","website":"www.madani.sch.id","direktur":"Dr. H. Ahmad Fauzi, M.Pd.","npsn":"20104567"}'::jsonb,
 '{"mode":"hybrid","api_key":"","model":"gemini-3.8-flash","custom_model":""}'::jsonb,
 'seed'
) on conflict (id) do nothing;

-- 7.2 30 pegawai contoh
insert into public.pegawai (id,nip,nama,jk,tempat_lahir,tgl_lahir,pendidikan,jabatan,unit,jenis_pegawai,tgl_masuk,status,kontrak_sampai,gaji_pokok,email,telepon,alamat) values
('pg01','196905122005011001','Dr. H. Ahmad Fauzi, M.Pd.','L','Jakarta','1969-05-12','S3 Manajemen Pendidikan','Direktur Utama','Direktorat','Guru Tetap','2005-01-11','Aktif',null,18500000,'direktur@madani.sch.id','0812-1000-001','Jl. Kemang Selatan No. 8, Jakarta Selatan'),
('pg02','197803242010012002','Rina Kartika, S.Psi., M.M.','P','Bandung','1978-03-24','S2 Psikologi Industri','Manajer HRD','Kepegawaian & SDM','Guru Tetap','2010-01-25','Aktif',null,14500000,'manajer@madani.sch.id','0812-1000-002','Jl. Cipete Raya No. 12, Jakarta Selatan'),
('pg03','198206102012011003','Bambang Setiawan, S.H., M.H.','L','Surabaya','1982-06-10','S2 Hukum','Kepala Bidang SDM & Legal','Kepegawaian & SDM','Guru Tetap','2012-02-13','Aktif',null,12800000,'kabid@madani.sch.id','0812-1000-003','Jl. Pondok Indah No. 21, Jakarta Selatan'),
('pg04','198511302014012004','Dewi Anggraeni, S.AP.','P','Semarang','1985-11-30','S2 Administrasi Publik','Kepala Bidang Pengembangan SDM','Kepegawaian & SDM','Guru Tetap','2014-01-15','Aktif',null,12200000,'kabid2@madani.sch.id','0812-1000-004','Jl. Tebet Timur No. 5, Jakarta Selatan'),
('pg05','199002182018011005','Fajar Nugroho, S.Kom.','L','Jakarta','1990-02-18','S1 Sistem Informasi','Staf Kepegawaian','Kepegawaian & SDM','Tenaga Kekaryaan','2018-03-01','Aktif','2026-12-31',7800000,'kepegawaian@madani.sch.id','0812-1000-005','Jl. Mampang Prapatan No. 33, Jakarta Selatan'),
('pg06','199206242019012006','Siti Nurhaliza, A.Md.','P','Bogor','1992-06-24','D3 Manajemen Kepegawaian','Staf Kepegawaian','Kepegawaian & SDM','Tenaga Kekaryaan','2019-07-01','Aktif','2026-09-30',7200000,'staf.kep@madani.sch.id','0812-1000-006','Jl. Cibinong Raya No. 9, Bogor'),
('pg07','198809152016011007','Andi Prasetyo, S.Pd., M.Pd.','L','Yogyakarta','1988-09-15','S2 Manajemen Pendidikan','Staf Kinerja & Pengembangan SDM','Kepegawaian & SDM','Guru Tetap','2016-08-01','Aktif',null,9500000,'kinerja@madani.sch.id','0812-1000-007','Jl. Kalibata Timur No. 17, Jakarta Selatan'),
('pg08','197501202005011008','Dra. Sri Wahyuni, M.M.','P','Medan','1975-01-20','S2 Manajemen','Kepala Sekolah','SMP Madani','Guru Tetap','2005-07-01','Aktif',null,13500000,'kepsek@madani.sch.id','0812-1000-008','Jl. Kebayoran Lama No. 40, Jakarta Selatan'),
('pg09','198005112008011009','Hendrawan, S.Pd.','L','Palembang','1980-05-11','S1 Pendidikan Matematika','Guru Matematika','SMP Madani','Guru Tetap','2008-07-15','Aktif',null,8500000,'hendrawan@madani.sch.id','0812-1000-009','Jl. Pasar Minggu No. 22, Jakarta Selatan'),
('pg10','199103062017012010','Maya Lestari, S.Pd.','P','Kediri','1991-03-06','S1 Pendidikan Bahasa Inggris','Guru Bahasa Inggris','SMP Madani','Guru Tetap','2017-07-10','Aktif','2026-11-30',8000000,'maya@madani.sch.id','0812-1000-010','Jl. Cilandak Timur No. 3, Jakarta Selatan'),
('pg11','199507192021011011','Rizky Ramadhan, S.Pd.','L','Serang','1995-07-19','S1 Pendidikan IPA','Guru IPA','SMP Madani','Guru Tidak Tetap','2021-07-19','Aktif','2026-12-19',6500000,'rizky@madani.sch.id','0812-1000-011','Jl. Raya Ragunan No. 55, Jakarta Selatan'),
('pg12','199704112022012012','Putri Maharani, S.Pd.','P','Tangerang','1997-04-11','S1 Pendidikan Bahasa Indonesia','Guru Bahasa Indonesia','SMP Madani','Guru Tidak Tetap','2022-01-10','Aktif','2026-12-10',6300000,'putri@madani.sch.id','0812-1000-012','Jl. TB Simatupang No. 77, Jakarta Selatan'),
('pg13','198402082010011013','Drs. Joko Santoso, M.Pd.','L','Solo','1984-02-08','S2 Administrasi Pendidikan','Kepala Sekolah','SMA Unggulan Madani','Guru Tetap','2010-02-09','Aktif',null,13200000,'kepsek.sma@madani.sch.id','0812-1000-013','Jl. Fatmawati No. 14, Jakarta Selatan'),
('pg14','198712232012012014','Lina Marlina, S.Si.','P','Padang','1987-12-23','S1 Kimia','Guru Kimia','SMA Unggulan Madani','Guru Tetap','2012-12-24','Aktif',null,8800000,'lina@madani.sch.id','0812-1000-014','Jl. Cipulir Raya No. 28, Jakarta Selatan'),
('pg15','198910042014011015','Agus Wibowo, S.Pd., Gr.','L','Malang','1989-10-04','S1 Pendidikan Fisika','Guru Fisika','SMA Unggulan Madani','Guru Tetap','2014-08-18','Aktif','2027-06-30',8400000,'agus@madani.sch.id','0812-1000-015','Jl. Lenteng Agung No. 61, Jakarta Selatan'),
('pg16','199304052019012016','Citra Ayu, S.Pd.','P','Denpasar','1993-04-05','S1 Pendidikan Biologi','Guru Biologi','SMA Unggulan Madani','Guru Tetap','2019-07-22','Aktif',null,7900000,'citra@madani.sch.id','0812-1000-016','Jl. Warung Buncit No. 20, Jakarta Selatan'),
('pg17','199608212022011017','Dimas Prakoso, S.Pd.','L','Kupang','1996-08-21','S1 Pendidikan Sejarah','Guru Sejarah','SMA Unggulan Madani','Guru Tidak Tetap','2022-08-01','Aktif','2026-11-14',6400000,'dimas@madani.sch.id','0812-1000-017','Jl. Margasatwa No. 7, Jakarta Selatan'),
('pg18','199110162018012018','Nadia Safitri, S.Pd.I.','P','Mataram','1991-10-16','S1 Pendidikan Agama Islam','Guru Agama Islam','SD Madani Gemilang','Guru Tetap','2018-01-08','Aktif',null,7600000,'nadia@madani.sch.id','0812-1000-018','Jl. Pejaten Barat No. 11, Jakarta Selatan'),
('pg19','198606072011011019','Budi Hartono, S.Pd.','L','Pekanbaru','1986-06-07','S1 Pendidikan Matematika','Guru Kelas','SD Madani Gemilang','Guru Tetap','2011-07-11','Aktif',null,8200000,'budi@madani.sch.id','0812-1000-019','Jl. Pasar Minggu No. 90, Jakarta Selatan'),
('pg20','199402262020012020','Ratna Dewi, S.Pd.','P','Manado','1994-02-26','S1 Pendidikan Guru Sekolah Dasar','Guru Kelas','SD Madani Gemilang','Guru Tetap','2020-07-13','Aktif','2026-10-20',7400000,'ratna@madani.sch.id','0812-1000-020','Jl. Cipete Utama No. 4, Jakarta Selatan'),
('pg21','199809052023011021','Yoga Saputra, S.Pd.','L','Pontianak','1998-09-05','S1 Pendidikan Olahraga','Guru Penjas','SD Madani Gemilang','Guru Tidak Tetap','2023-07-17','Aktif','2026-12-17',6100000,'yoga@madani.sch.id','0812-1000-021','Jl. Ulujami Raya No. 32, Jakarta Selatan'),
('pg22','199501102021012022','Intan Permata, S.Pd.','P','Jayapura','1995-01-10','S1 Pendidikan Anak Usia Dini','Guru Kelas','SD Madani Gemilang','Guru Tidak Tetap','2021-01-11','Aktif','2026-11-11',6200000,'intan@madani.sch.id','0812-1000-022','Jl. Kalibata Kecil No. 2, Jakarta Selatan'),
('pg23','198307182009011023','Eko Purnomo, S.E.','L','Sragen','1983-07-18','S1 Akuntansi','Kepala Keuangan','Keuangan','Tenaga Kekaryaan','2009-03-02','Aktif',null,11800000,'keuangan@madani.sch.id','0812-1000-023','Jl. Batu Tumpeng No. 6, Jakarta Selatan'),
('pg24','199303292019012024','Wulan Sari, A.Md.','P','Cirebon','1993-03-29','D3 Akuntansi','Staf Keuangan','Keuangan','Tenaga Kekaryaan','2019-02-04','Cuti','2026-12-31',6800000,'wulan@madani.sch.id','0812-1000-024','Jl. Cempaka Putih No. 15, Jakarta Pusat'),
('pg25','198508242012011025','Slamet Riyadi','L','Klaten','1985-08-24','SMA','Kepala Tata Usaha','Tata Usaha','Tenaga Kekaryaan','2012-05-14','Aktif',null,7500000,'tu@madani.sch.id','0812-1000-025','Jl. Ragunan Raya No. 48, Jakarta Selatan'),
('pg26','199701172022012026','Aisyah Putri, A.Md.','P','Bekasi','1997-01-17','D3 Perpustakaan','Pustakawan','Tata Usaha','Tenaga Kekaryaan','2022-02-07','Aktif','2026-10-30',5900000,'perpus@madani.sch.id','0812-1000-026','Jl. Cibubur Raya No. 19, Bekasi'),
('pg27','199204222018011027','Gunawan Wibisono','L','Salatiga','1992-04-22','SMK Teknik Komputer','Teknisi & IT Support','Tata Usaha','Karyawan Harian','2018-06-11','Aktif',null,5600000,'it@madani.sch.id','0812-1000-027','Jl. Depok Raya No. 25, Depok'),
('pg28','196809032005012028','Sukarno, B.A.','L','Surakarta','1968-09-03','S1 Bahasa dan Sastra Indonesia','Kepala Unit Pengembangan Kurikulum','Direktorat','Guru Tetap','2005-12-01','Aktif',null,12800000,'kurikulum@madani.sch.id','0812-1000-028','Jl. Jati Padang Raya No. 10, Jakarta Selatan'),
('pg29','198403102011012029','Endang Kusuma, S.Pd.','P','Magelang','1984-03-10','S1 Bimbingan Konseling','Konselor Sekolah','SMP Madani','Guru Tetap','2011-03-14','Izin','2027-03-31',8100000,'bk@madani.sch.id','0812-1000-029','Jl. Pejatenn Timur No. 88, Jakarta Selatan'),
('pg30','198112122006011030','Hadi Susanto, S.T.','L','Batam','1981-12-12','S1 Teknik Sipil','Kepala Unit Sarana & Prasarana','Tata Usaha','Tenaga Kekaryaan','2006-08-01','Aktif','2026-12-28',10200000,'sarpras@madani.sch.id','0812-1000-030','Jl. Lenteng Agung Atas No. 3, Jakarta Selatan')
on conflict (id) do nothing;

-- 7.3 Contoh surat
insert into public.surat (id,jenis,nomor,perihal,penerima,status,tahap,tanggal,created_by,payload) values
('st01','Surat Tugas','012/HRD-TGS/X/2025','Surat Tugas Menghadiri Bimtek Manajemen Sekolah','Bambang Setiawan, S.H., M.H.','Terbit',7,'2025-10-10','manajer@madani.sch.id','{"isi":"Surat tugas resmi menghadiri Bimtek di Bandung 20-22 Oktober 2025.","params":{}}'::jsonb),
('st02','Surat Keterangan Kerja','018/HRD-KK/X/2025','Keterangan Bekerja untuk keperluan kredit bank','Maya Lestari, S.Pd.','Terbit',7,'2025-10-14','staf.kep@madani.sch.id','{"isi":"Yang bertanda tangan di bawah ini menerangkan bahwa yang bersangkutan benar merupakan pegawai aktif Yayasan Pendidikan Madani.","params":{}}'::jsonb),
('st03','Permohonan Izin Cuti','021/HRD-CUTI/X/2025','Permohonan Cuti Tahunan 5 Hari','Wulan Sari, A.Md.','Disetujui',6,'2025-10-20','wulan@madani.sch.id','{"isi":"Permohonan cuti tahunan 25-29 November 2025.","params":{}}'::jsonb),
('st04','Surat Perpanjangan Kontrak Kerja','023/HRD-PKP/X/2025','Perpanjangan Kontrak Kerja Guru Tidak Tetap','Rizky Ramadhan, S.Pd.','Dalam Review',2,'2025-10-28','kepegawaian@madani.sch.id','{"isi":"Pemberitahuan perpanjangan kontrak kerja periode Desember 2026 - Desember 2027.","params":{}}'::jsonb),
('st05','Surat Keputusan (SK) Pengangkatan','001/YP-KEP/XI/2025','SK Pengangkatan Kepala Unit Sarana & Prasarana','Hadi Susanto, S.T.','Menunggu Persetujuan',4,'2025-11-02','manajer@madani.sch.id','{"isi":"Menetapkan pengangkatan Hadi Susanto, S.T. sebagai Kepala Unit Sarana & Prasarana.","params":{}}'::jsonb)
on conflict (id) do nothing;

-- 7.4 Contoh dokumen (SOP/IK/JD/Pedoman/Kebijakan)
insert into public.dokumen (id,kategori,judul,nomor,versi,status,tahap,tanggal,kedaluwarsa,created_by,payload) values
('dk01','SOP','SOP Rekrutmen dan Seleksi Pegawai','SOP-HRD-001',2,'Terbit',7,'2024-01-15','2026-12-31','manajer@madani.sch.id','{"konten":"Dokumen SOP lengkap 20 bagian: tujuan, definisi, ruang lingkup, prosedur, flowchart, analisis risiko.","riwayat":[]}'::jsonb),
('dk02','Instruksi Kerja','IK Pengoperasian Sistem Absensi Fingerprint','IK-HRD-004',1,'Terbit',7,'2024-03-02','2026-12-31','kabid@madani.sch.id','{"konten":"Langkah teknis pengoperasian absensi: inisialisasi, registrasi sidik jari, sinkronisasi data, penanganan kendala.","riwayat":[]}'::jsonb),
('dk03','Deskripsi Jabatan','Deskripsi Jabatan Guru Mata Pelajaran','DJ-DIK-002',1,'Terbit',7,'2024-02-10','2026-12-31','kabid2@madani.sch.id','{"konten":"Deskripsi jabatan 20 bagian untuk guru: tugas pokok, kompetensi, indikator kinerja, jenjang karier.","riwayat":[]}'::jsonb),
('dk04','Pedoman','Pedoman Pemberian Cuti Pegawai','PD-HRD-003',1,'Terbit',7,'2024-04-01','2026-12-31','manajer@madani.sch.id','{"konten":"Pedoman cuti tahunan, sakit, melahirkan, penting dengan struktur bab dan subbab.","riwayat":[]}'::jsonb),
('dk05','Kebijakan & Regulasi','Peraturan Kepegawaian Yayasan Pendidikan Madani','PR-YPM-001',3,'Perlu Revisi',1,'2024-05-20','2026-12-31','manajer@madani.sch.id','{"konten":"Peraturan kepegawaian menyeluruh: kedudukan, rekrutmen, hak-kewajiban, disiplin, PHK. Revisi menunggu tinjauan klausul PP 35/2021.","riwayat":[]}'::jsonb),
('dk06','Pedoman','Pedoman Penilaian Kinerja Pegawai','PD-HRD-006',1,'Diajukan',2,'2025-09-15','2026-12-31','kinerja@madani.sch.id','{"konten":"Pedoman penilaian kinerja berbasis KPI SMART dengan evaluasi triwulanan.","riwayat":[]}'::jsonb)
on conflict (id) do nothing;

-- 7.5 Contoh arsip (Modul 10 — mendukung tombol Edit dan Riwayat Versi)
insert into public.arsip (id,judul,kategori,nomor,tanggal_dokumen,unit,pic,kerahasiaan,status,deskripsi,kedaluwarsa,versi,file_name,file_size,created_by) values
('ar01','SK Pengangkatan Manajer HRD 2023','Surat Keputusan (SK)','001/YP-KEP/I/2023','2023-01-05','Direktorat','Rina Kartika, S.Psi., M.M.','Internal','Aktif','SK pengangkatan Manajer HRD periode 2023-2026','2026-01-05',2,'SK-Pengangkatan-HRD-2023.pdf',284512,'admin@madani.sch.id'),
('ar02','Perjanjian Kerja Waktu Tertentu (PKWT) Guru 2025','Perjanjian Kerja','PKWT/2025/011','2025-01-10','Kepegawaian & SDM','Fajar Nugroho, S.Kom.','Rahasia','Aktif','PKWT 11 guru tidak tetap periode Januari-Desember 2025','2026-01-10',1,'PKWT-Guru-2025.pdf',1024000,'admin@madani.sch.id'),
('ar03','Berita Acara Serah Terima Jabatan Kepala TU','Berita Acara','BA/ST/2025/004','2025-02-20','Tata Usaha','Slamet Riyadi','Internal','Aktif','Berita acara serah terima dokumen dan aset Tata Usaha','2027-02-20',1,'BA-Serah-Terima-TU.pdf',198320,'admin@madani.sch.id'),
('ar04','Laporan Kinerja HRD Triwulan III 2025','Laporan Kinerja','LK-HRD/TW-III/2025','2025-10-05','Kepegawaian & SDM','Andi Prasetyo, S.Pd., M.Pd.','Internal','Aktif','Laporan capaian KPI HRD triwulan ketiga','2027-10-05',1,'LK-HRD-TW3-2025.xlsx',84221,'kinerja@madani.sch.id'),
('ar05','Tata Tertib Pegawai Edisi 2024','Kebijakan & Regulasi','TT-YPM/2024/001','2024-06-01','Direktorat','Bambang Setiawan, S.H., M.H.','Publik','Aktif','Tata tertib lengkap beserta sanksi bertingkat','2027-06-01',3,'Tata-Tertib-2024.pdf',512000,'admin@madani.sch.id'),
('ar06','SOP Perpustakaan Sekolah (Arsip Lama)','SOP','SOP-TU-012','2020-08-11','Tata Usaha','Aisyah Putri, A.Md.','Internal','Kedaluwarsa','SOP versi lama, telah digantikan SOP-TU-012 rev.2','2024-08-11',1,'SOP-Perpustakaan-2020.pdf',176400,'admin@madani.sch.id'),
('ar07','Surat Edaran Libur Semester Ganjil','Surat Menyurat','SE/120/2025','2025-11-25','Direktorat','Sukarno, B.A.','Publik','Aktif','Edaran jadwal libur dan kegiatan semester','2026-12-31',1,'SE-Libur-Semester.pdf',91240,'admin@madani.sch.id'),
('ar08','Pedoman Orientasi Pegawai Baru 2025','Pedoman','PD-HRD-009','2025-03-01','Kepegawaian & SDM','Dewi Anggraeni, S.AP.','Internal','Aktif','Pedoman induksi 3 hari untuk pegawai baru','2027-03-01',1,'Pedoman-Orientasi-2025.pdf',233800,'admin@madani.sch.id'),
('ar09','Instruksi Kerja Penanganan Arsip Elektronik','Instruksi Kerja','IK-TU-007','2024-11-01','Tata Usaha','Aisyah Putri, A.Md.','Internal','Aktif','Prosedur teknis scan, penamaan, dan backup arsip','2026-11-01',1,'IK-Arsip-Elektronik.pdf',145200,'admin@madani.sch.id'),
('ar10','Deskripsi Jabatan Staf Keuangan','Deskripsi Jabatan','DJ-KEU-001','2024-01-20','Keuangan','Eko Purnomo, S.E.','Internal','Aktif','Deskripsi jabatan staf keuangan 20 bagian','2027-01-20',1,'DJ-Staf-Keuangan.pdf',121000,'admin@madani.sch.id'),
('ar11','Data Rekap Absensi Oktober 2025','Dokumen Lainnya','ABS/2025/10','2025-10-31','Kepegawaian & SDM','Siti Nurhaliza, A.Md.','Rahasia','Aktif','Rekapitulasi absensi seluruh pegawai Oktober 2025','2027-10-31',1,'Rekap-Absensi-Okt2025.xlsx',68412,'staf.kep@madani.sch.id')
on conflict (id) do nothing;

-- 7.6 Riwayat versi arsip (contoh: ar01 sudah versi 2, ar05 sudah versi 3)
insert into public.arsip_versi (id,arsip_id,versi,diubah_oleh,perubahan,snapshot) values
('av01','ar01',1,'admin@madani.sch.id','Pembuatan arsip awal','{"judul":"SK Pengangkatan Manajer HRD 2023","status":"Aktif"}'::jsonb),
('av02','ar01',2,'admin@madani.sch.id','Memperbarui: kedaluwarsa (perpanjangan masa berlaku SK)','{"judul":"SK Pengangkatan Manajer HRD 2023","kedaluwarsa":"2026-01-05"}'::jsonb),
('av03','ar05',1,'admin@madani.sch.id','Pembuatan arsip awal','{"judul":"Tata Tertib Pegawai Edisi 2024"}'::jsonb),
('av04','ar05',2,'manajer@madani.sch.id','Memperbarui: deskripsi, tambahan sanksi level 3','{"judul":"Tata Tertib Pegawai Edisi 2024"}'::jsonb),
('av05','ar05',3,'admin@madani.sch.id','Memperbarui: versi dokumen edisi 2024 final','{"judul":"Tata Tertib Pegawai Edisi 2024","versi":3}'::jsonb)
on conflict (id) do nothing;

-- 7.7 KPI + realisasi (cascading: Direktur -> Unit -> Individu)
insert into public.kpi (id,nama,deskripsi,level,parent_kpi,unit,pic,target,satuan,baseline,periode,batas_waktu,payload) values
('kp01','Meningkatkan Kualitas Layanan Pendidikan (rata-rata akreditasi unit)','KPI strategis yayasan: menjaga dan meningkatkan akreditasi seluruh unit pendidikan minimal A (baik sekali)','Direktur',null,'Direktorat','Dr. H. Ahmad Fauzi, M.Pd.',100,'%','88','2026','2026-12-31','{"smart":{"s":"Akreditasi seluruh unit (SD, SMP, SMA) berdasarkan sertifikat BAN-S/M","m":"Rata-rata nilai akreditasi >= 90 dengan predikat A","a":"Baseline rata-rata 88 (predikat B) pada 2025; kenaikan 2 poin realistis dengan program pendampingan","r":"Selaras visi yayasan menjadi lembaga pendidikan unggulan","t":"Dicapai paling lambat 31 Desember 2026"},"evaluasi":[]}'::jsonb),
('kp02','Tingkat retensi pegawai (turnover maksimal)','Menjaga turnover tahunan di bawah 8%','Unit','kp01','Kepegawaian & SDM','Rina Kartika, S.Psi., M.M.',8,'%','9.5','2026','2026-12-31','{"smart":{"s":"Turnover dihitung dari keluar/masuk pegawai aktif per 31 Desember","m":"Turnover <= 8%","a":"2025: 9,5% dengan program retensi & kepuasan pegawai","r":"Menopang stabilitas kualitas layanan pendidikan (KPI Direktur)","t":"Diukur setiap akhir triwulan"},"evaluasi":[]}'::jsonb),
('kp03','Ketepatan administrasi kepegawaian','Seluruh surat & dokumen kepegawaian terbit tepat waktu tanpa kesalahan administrasi','Unit','kp01','Kepegawaian & SDM','Bambang Setiawan, S.H., M.H.',100,'%','95','2026','2026-12-31','{"smart":{"s":"Surat, SK, dan dokumen legal terbit sesuai SLA 5 hari kerja","m":"Ketepatan >= 100 dokumen dinilai","a":"Baseline 95% pada 2025 dengan penerapan SMART HRD","r":"Mendukung kepatuhan legal kepegawaian","t":"Dievaluasi tiap triwulan"},"evaluasi":[]}'::jsonb),
('kp04','Mengurangi turnover guru SMP','Menahan turnover guru SMP di bawah 6% lewat program pengembangan','Individu','kp02','SMP Madani','Dra. Sri Wahyuni, M.M.',6,'%','8','2026','2026-12-31','{"smart":{"s":"Retensi guru SMP melalui mentoring dan pelatihan","m":"Turnover guru SMP <= 6%","a":"Baseline 8% (2025)","r":"Turunan langsung KPI unit SDM","t":"31 Desember 2026"},"evaluasi":[]}'::jsonb),
('kp05','Pelaksanaan pelatihan internal (jam pelatihan)','Menyelenggarakan minimal 24 jam pelatihan internal per tahun','Individu','kp02','Kepegawaian & SDM','Dewi Anggraeni, S.AP.',24,'jam/tahun','18','2026','2026-12-31','{"smart":{"s":"Pelatihan pedagogik, administrasi, dan K3 untuk seluruh unit","m":"Akumulasi >= 24 jam efektif","a":"Baseline 18 jam (2025), bertambah 6 jam dari e-learning","r":"Mendukung pengembangan kompetensi (renstra SDM)","t":"Dipantau tiap triwulan"},"evaluasi":[]}'::jsonb),
('kp06','Kelengkapan arsip digital pegawai','Seluruh berkas pegawai terdigitalisasi dan terarsip di DMS','Individu','kp03','Kepegawaian & SDM','Fajar Nugroho, S.Kom.',100,'%','85','2026','2026-12-31','{"smart":{"s":"Digitalisasi SK, PKWT, ijazah, sertifikat seluruh pegawai","m":"Kelengkapan 100% berkas (cek bulanan)","a":"Baseline 85% (2025)","r":"Mendukung ketepatan administrasi kepegawaian","t":"Selesai 31 Desember 2026"},"evaluasi":[]}'::jsonb)
on conflict (id) do nothing;

insert into public.kpi_realisasi (id,kpi_id,periode,realisasi,catatan,dinilai_oleh) values
('kr01','kp01','TW-1',95,'Akreditasi SMP terbit A; SMA dalam proses','admin@madani.sch.id'),
('kr02','kp01','TW-2',97,'SD naik ke predikat A','admin@madani.sch.id'),
('kr03','kp01','TW-3',97,'Konsolidasi dokumen SMA','admin@madani.sch.id'),
('kr04','kp02','TW-1',9.0,'Turnover awal tahun','admin@madani.sch.id'),
('kr05','kp02','TW-2',8.5,'Program retensi mulai efektif','admin@madani.sch.id'),
('kr06','kp02','TW-3',8.0,'Tren menurun sesuai target','admin@madani.sch.id'),
('kr07','kp03','TW-1',100,'SLA surat terpenuhi','admin@madani.sch.id'),
('kr08','kp03','TW-2',98,'1 SK melewati SLA 2 hari','admin@madani.sch.id'),
('kr09','kp03','TW-3',100,'Administrasi lancar','admin@madani.sch.id'),
('kr10','kp04','TW-1',8.0,'2 guru resign','kepsek@madani.sch.id'),
('kr11','kp04','TW-2',7.0,'Mentoring dimulai','kepsek@madani.sch.id'),
('kr12','kp04','TW-3',6.5,'Mendekati target','kepsek@madani.sch.id'),
('kr13','kp05','TW-1',6,'Pelatihan K3 & kurikulum','kinerja@madani.sch.id'),
('kr14','kp05','TW-2',13,'Tambah pelatihan e-learning','kinerja@madani.sch.id'),
('kr15','kp05','TW-3',21,'Kurang 3 jam dari target tahunan','kinerja@madani.sch.id'),
('kr16','kp06','TW-1',89,'Digitalisasi SK & PKWT selesai','kinerja@madani.sch.id'),
('kr17','kp06','TW-2',93,'Sertifikat guru masuk DMS','kinerja@madani.sch.id'),
('kr18','kp06','TW-3',96,'Sisa berkas alumni lama','kinerja@madani.sch.id')
on conflict (id) do nothing;

-- 7.8 Agenda
insert into public.agenda (id,judul,tanggal,waktu,tempat,peserta,keterangan,created_by) values
('ag01','Rapat Evaluasi Kinerja Triwulan IV','2026-11-06','09:00-11:30','Ruang Rapat Utama','Direktur, Manajer HRD, Kepala Bidang, Kepala Unit','Pembahasan capaian KPI TW-4','manajer@madani.sch.id'),
('ag02','Pelatihan K3 dan Pemadaman Kebakaran','2026-11-12','13:00-16:00','Lapangan Utama','Seluruh pegawai','Bekerja sama dengan Damkar Jakarta Selatan','kabid2@madani.sch.id'),
('ag03','Wawancara Calon Guru Tidak Tetap','2026-11-18','08:30-12:00','Ruang Interview HRD','Panitia rekrutmen','3 kandidat guru IPA & Matematika','kabid@madani.sch.id'),
('ag04','Pembagian THR dan Pengumuman Kenaikan Gaji','2026-11-27','10:00-11:00','Aula Yayasan','Seluruh pegawai','Serah terima surat keputusan kenaikan gaji','manajer@madani.sch.id')
on conflict (id) do nothing;

-- 7.9 Notifikasi awal
insert into public.notifikasi (id,user_email,target_role,judul,pesan,tipe,dibaca) values
('nt01',null,'manajer_hrd','Kontrak Pegawai Segera Berakhir','9 pegawai memiliki kontrak yang berakhir dalam 90 hari ke depan. Segera proses perpanjangan.','peringatan',false),
('nt02',null,'staf_kepegawaian','Dokumen Menunggu Verifikasi','2 dokumen menunggu verifikasi pada Tahap 2 (Pusat Persetujuan).','info',false),
('nt03',null,'direktur','SK Menunggu Persetujuan','SK Pengangkatan Kepala Unit Sarana & Prasarana menunggu persetujuan Anda.','info',false)
on conflict (id) do nothing;

-- 7.10 Contoh audit log
insert into public.audit_log (id,user_email,user_role,aksi,entitas,entitas_id,detail) values
('al01','admin@madani.sch.id','admin_sistem','SEED','sistem','global','Inisialisasi basis data SMART HRD melalui SQL Editor')
on conflict (id) do nothing;

-- ============================================================================
-- 8. AKUN DEMO (DIBUAT OTOMATIS — password semua akun: Madani2026)
-- ----------------------------------------------------------------------------
-- Blok ini mencoba membuat 8 akun login langsung di Supabase Auth. Jika
-- lingkungan proyek Anda melarang insert ke auth.users, blok ini DILEWATI
-- dengan aman (skrip tetap sukses) — buat user manual lewat:
--   Authentication -> Users -> Add user (centang "Auto Confirm User")
--   lalu JALANKAN ULANG skrip ini agar role & profil terisi otomatis.
-- ============================================================================
do $$
declare
  r record; uid uuid; pwd text := 'Madani2026';
begin
  for r in select * from (values
    ('a1b2c3d4-0000-4000-8000-000000000001','admin@madani.sch.id',        'Admin Sistem',               'admin_sistem',    'Administrator Sistem',              'Kepegawaian & SDM'),
    ('a1b2c3d4-0000-4000-8000-000000000002','manajer@madani.sch.id',      'Rina Kartika, S.Psi., M.M.', 'manajer_hrd',     'Manajer HRD',                       'Kepegawaian & SDM'),
    ('a1b2c3d4-0000-4000-8000-000000000003','kabid@madani.sch.id',        'Bambang Setiawan, S.H., M.H.','kepala_bidang',  'Kepala Bidang SDM & Legal',         'Kepegawaian & SDM'),
    ('a1b2c3d4-0000-4000-8000-000000000004','kepegawaian@madani.sch.id',  'Fajar Nugroho, S.Kom.',      'staf_kepegawaian','Staf Kepegawaian',                  'Kepegawaian & SDM'),
    ('a1b2c3d4-0000-4000-8000-000000000005','kinerja@madani.sch.id',      'Andi Prasetyo, S.Pd., M.Pd.','staf_kinerja',    'Staf Kinerja & Pengembangan SDM',   'Kepegawaian & SDM'),
    ('a1b2c3d4-0000-4000-8000-000000000006','direktur@madani.sch.id',     'Dr. H. Ahmad Fauzi, M.Pd.',  'direktur',        'Direktur Utama',                    'Direktorat'),
    ('a1b2c3d4-0000-4000-8000-000000000007','kepsek@madani.sch.id',       'Dra. Sri Wahyuni, M.M.',     'kepala_unit',     'Kepala SMP Madani',                 'SMP Madani'),
    ('a1b2c3d4-0000-4000-8000-000000000008','pegawai@madani.sch.id',      'Maya Lestari, S.Pd.',        'pegawai',         'Guru Bahasa Inggris',               'SMP Madani')
  ) as t(id,email,nama,role,jabatan,unit)
  loop
    uid := r.id::uuid;
    begin
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change, email_change_token_new
      ) values (
        '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
        r.email, crypt(pwd, gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('nama',r.nama,'role',r.role,'jabatan',r.jabatan,'unit',r.unit),
        now(), now(), '', '', '', ''
      ) on conflict do nothing;

      insert into auth.identities (user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (uid, uid::text,
              jsonb_build_object('sub', uid::text, 'email', r.email, 'email_verified', true),
              'email', now(), now(), now())
      on conflict do nothing;
    exception when others then
      raise notice 'Lewati pembuatan auth user %: % (buat manual via Authentication, lalu jalankan ulang skrip)', r.email, sqlerrm;
    end;

    -- Profil + role dibuat/diperbarui (berlaku juga bila user dibuat manual)
    insert into public.profiles (id, email, nama, role, jabatan, unit)
    values (uid, r.email, r.nama, r.role, r.jabatan, r.unit)
    on conflict (email) do update set
      id = excluded.id, nama = excluded.nama, role = excluded.role,
      jabatan = excluded.jabatan, unit = excluded.unit, updated_at = now();
  end loop;
  raise notice 'SEED SELESAI — akun demo (password: Madani2026): admin@ / manajer@ / kabid@ / kepegawaian@ / kinerja@ / direktur@ / kepsek@ / pegawai@ (domain madani.sch.id)';
end $$;

-- ============================================================================
-- CATATAN AKUN LOGIN (PELENGKAP BAGIAN 8)
-- ----------------------------------------------------------------------------
-- 8 akun demo (password: Madani2026) sudah dibuat otomatis di bagian 8:
--   admin@madani.sch.id         → Admin Sistem
--   manajer@madani.sch.id       → Manajer HRD
--   kabid@madani.sch.id         → Kepala Bidang HRD
--   kepegawaian@madani.sch.id   → Staf Kepegawaian
--   kinerja@madani.sch.id       → Staf Kinerja & Pengembangan SDM
--   direktur@madani.sch.id      → Direktur
--   kepsek@madani.sch.id        → Kepala Unit/Sekolah
--   pegawai@madani.sch.id       → Pegawai
-- Bila blok otomatis terlewati (kebijakan proyek), buat user manual di
-- Authentication -> Users -> Add user (centang "Auto Confirm User"), lalu
-- JALANKAN ULANG skrip ini — profil & role terisi otomatis oleh bagian 8.
-- Untuk user tambahan di luar 8 akun demo, atur role-nya dengan pola:
--   update public.profiles set role='pegawai' where email='nama@madani.sch.id';
-- Alternatif cepat: aplikasi SMART HRD juga menyediakan MODE LOKAL (demo)
-- berjalan tanpa Supabase — 8 akun demo tersedia di halaman login.
-- ============================================================================
-- SELESAI — SMART HRD siap digunakan. Selamat bekerja! 🎉
