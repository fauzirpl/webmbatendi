-- =============================================================
-- Skema database — Pelepasan Tandika
-- =============================================================
-- Berkas ini cerminan keadaan Supabase saat ditulis, diambil langsung dari
-- katalog database (pg_policies, pg_get_functiondef, information_schema),
-- bukan dari ingatan.
--
-- Gunanya dua: jadi acuan kalau projeknya perlu dibangun ulang dari nol, dan
-- jadi tempat mencatat alasan di balik keputusan yang tidak kelihatan dari
-- kodenya. Halaman webnya statis — separuh aplikasi ini sebenarnya ada di
-- sini, dan tanpa berkas ini separuh itu tidak punya jejak di repo.
--
-- Urutannya sudah benar untuk dijalankan sekali jalan di SQL Editor projek
-- Supabase yang masih kosong.
--
-- Projek asal: djzzayvisldfuczhqmjb (region ap-southeast-1)


-- =============================================================
-- 1. Siapa yang boleh mengelola
-- =============================================================
-- Daftar-putih, bukan sekadar mengandalkan role 'authenticated'. Kalau
-- pendaftaran publik kelupaan dimatikan, orang asing yang berhasil daftar
-- tetap tidak bisa mengubah apa pun.

create table public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  catatan    text,
  created_at timestamptz not null default now()
);

alter table public.admins enable row level security;

-- Sengaja TANPA policy sama sekali, dan grant bawaan dicabut: tabel ini
-- tidak bisa disentuh lewat API, hanya lewat SQL Editor / service_role.
revoke all on public.admins from anon, authenticated;

create function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;


-- =============================================================
-- 2. Ucapan
-- =============================================================

create table public.wishes (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  msg         text not null,
  att         text not null default 'Datang',
  owner_token uuid not null,
  created_at  timestamptz not null default now(),

  -- Batas divalidasi di sini, bukan cuma di form. Request langsung ke API
  -- tidak lewat form, jadi form saja bukan pengamanan.
  constraint wishes_name_len  check (char_length(btrim(name)) between 1 and 42),
  constraint wishes_msg_len   check (char_length(btrim(msg))  between 2 and 420),
  constraint wishes_att_valid check (att in ('Datang', 'Absen'))
);

create index wishes_created_at_idx on public.wishes (created_at desc);

alter table public.wishes enable row level security;

-- Grant PER KOLOM. owner_token sengaja tidak ikut di grant select: tidak ada
-- cara bagi pengunjung membaca token orang lain, jadi tidak bisa menghapus
-- ucapan orang lain.
--
-- Konsekuensi yang harus diingat: klien WAJIB menyebut kolomnya satu per satu
-- (select=id,name,msg,att,created_at). 'select=*' akan ditolak — itu memang
-- disengaja, bukan bug.
revoke all on public.wishes from anon, authenticated;
grant select (id, name, msg, att, created_at) on public.wishes to anon, authenticated;
grant insert (name, msg, att, owner_token)    on public.wishes to anon, authenticated;
grant delete on public.wishes to authenticated;   -- digerbangi policy admin di bawah

create policy wishes_public_read
  on public.wishes for select to anon, authenticated using (true);

create policy wishes_public_insert
  on public.wishes for insert to anon, authenticated with check (true);

-- Moderasi: admin boleh menghapus ucapan siapa pun. Ucapannya dibacakan di
-- depan orang banyak, jadi ini perlu.
create policy wishes_admin_delete
  on public.wishes for delete to authenticated using (public.is_admin());

-- Sengaja TIDAK ada policy UPDATE, dan tidak ada policy DELETE untuk anon.
-- Penulis biasa menghapus ucapannya sendiri lewat fungsi di bawah.

create function public.delete_wish(p_id uuid, p_token uuid)
returns boolean
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  n int;
begin
  delete from public.wishes where id = p_id and owner_token = p_token;
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

revoke all on function public.delete_wish(uuid, uuid) from public;
grant execute on function public.delete_wish(uuid, uuid) to anon, authenticated;


-- =============================================================
-- 3. Konten yang bisa diedit (foto, stiker, teks, musik)
-- =============================================================
-- Panel admin membangun formulirnya dari isi tabel ini. Menambah kolom baru
-- di panel = INSERT satu baris di sini + satu binding di halaman. Tidak perlu
-- menyentuh kode panel sama sekali.

create table public.content (
  key        text primary key,
  value      text not null default '',
  label      text not null,          -- ditampilkan sebagai label di panel
  kind       text not null,          -- menentukan jenis input di panel
  grp        text not null,          -- pengelompokan di panel
  urutan     int  not null default 0,
  updated_at timestamptz not null default now(),

  constraint content_kind_check check (kind in ('teks', 'foto', 'audio'))
);

alter table public.content enable row level security;

revoke all on public.content from anon, authenticated;
grant select on public.content to anon, authenticated;
grant insert, update, delete on public.content to authenticated;

create policy content_public_read
  on public.content for select to anon, authenticated using (true);

create policy content_admin_write
  on public.content for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create function public.touch_content()
returns trigger language plpgsql
set search_path = public, pg_temp
as $$ begin new.updated_at = now(); return new; end; $$;

create trigger content_touch before update on public.content
  for each row execute function public.touch_content();


-- =============================================================
-- 4. Rundown acara
-- =============================================================
-- Tabel sendiri, bukan slot tetap di content, karena jumlah barisnya
-- berubah-ubah (tambah, hapus, geser).

create table public.rundown (
  id         uuid primary key default gen_random_uuid(),
  waktu      text not null,
  judul      text not null,
  catatan    text not null default '',
  urutan     int  not null default 0,
  created_at timestamptz not null default now(),

  constraint rundown_waktu_len   check (char_length(btrim(waktu)) between 1 and 12),
  constraint rundown_judul_len   check (char_length(btrim(judul)) between 1 and 80),
  constraint rundown_catatan_len check (char_length(catatan) <= 140)
);

create index rundown_urutan_idx on public.rundown (urutan);

alter table public.rundown enable row level security;

-- Hanya baca. Tidak ada grant tulis dan tidak ada policy tulis — satu-satunya
-- jalan mengubah rundown adalah fungsi di bawah.
revoke all on public.rundown from anon, authenticated;
grant select on public.rundown to anon, authenticated;

create policy rundown_public_read
  on public.rundown for select to anon, authenticated using (true);

-- Mengganti SELURUH rundown dalam satu transaksi. Menyimpan per-baris berisiko
-- putus di tengah dan membuat halaman yang sedang dibuka orang menampilkan
-- rundown separuh lama separuh baru.
--
-- ==> CATATAN PENTING soal DELETE-nya <==
-- Supabase memuat ekstensi `safeupdate` ke setiap koneksi PostgREST (lewat
-- session_preload_libraries pada role `authenticator`). Ekstensi itu menolak
-- DELETE tanpa WHERE — TERMASUK di dalam fungsi SECURITY DEFINER. Gejalanya:
-- "DELETE requires a WHERE clause" (SQLSTATE 21000).
--
-- Menambahkan WHERE asal-asalan TIDAK cukup. Sudah diperiksa lewat EXPLAIN:
--   WHERE true            -> qual dibuang perencana, tetap ditolak
--   WHERE id is not null  -> dibuang juga (id itu PK NOT NULL, terbukti benar)
--   WHERE id in (select)  -> jadi Hash Join, qual bertahan  <-- ini yang dipakai
--
-- Jadi jangan "menyederhanakan" baris DELETE di bawah. Kelihatannya berlebihan,
-- tapi bentuk itulah yang membuatnya lolos.
--
-- Pelajaran ujinya: bug ini TIDAK muncul kalau diuji lewat SQL Editor dengan
-- `set local role authenticated`, karena impersonasi role tidak memuat pustaka
-- yang menempel di koneksi. Apa pun yang berjalan lewat PostgREST harus diuji
-- lewat HTTP sungguhan.
create function public.simpan_rundown(p_rows jsonb)
returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  n int;
begin
  -- SECURITY DEFINER melewati RLS, jadi gerbangnya WAJIB dicek manual di sini
  if not public.is_admin() then
    raise exception 'Hanya admin yang boleh mengubah rundown';
  end if;

  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows harus berupa array';
  end if;

  if jsonb_array_length(p_rows) > 40 then
    raise exception 'Rundown maksimal 40 baris';
  end if;

  delete from public.rundown where id in (select id from public.rundown);

  insert into public.rundown (waktu, judul, catatan, urutan)
  select btrim(r.value->>'waktu'),
         btrim(r.value->>'judul'),
         coalesce(r.value->>'catatan', ''),
         r.ordinality::int
  from jsonb_array_elements(p_rows) with ordinality as r(value, ordinality);

  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.simpan_rundown(jsonb) from public, anon;
grant execute on function public.simpan_rundown(jsonb) to authenticated;


-- =============================================================
-- 5. Penyimpanan foto, stiker, dan musik
-- =============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('foto', 'foto', true, 12582912,
        array['image/jpeg','image/png','image/webp','image/gif',
              'audio/mpeg','audio/mp3','audio/mp4','audio/ogg','audio/wav'])
on conflict (id) do nothing;

create policy foto_public_read on storage.objects
  for select to anon, authenticated using (bucket_id = 'foto');

create policy foto_admin_insert on storage.objects
  for insert to authenticated with check (bucket_id = 'foto' and public.is_admin());

create policy foto_admin_update on storage.objects
  for update to authenticated using (bucket_id = 'foto' and public.is_admin());

create policy foto_admin_delete on storage.objects
  for delete to authenticated using (bucket_id = 'foto' and public.is_admin());


-- =============================================================
-- 6. Isi awal
-- =============================================================

insert into public.content (key, label, kind, grp, urutan, value) values
  ('foto.tandika-portrait', 'Foto Tandika (lingkaran)',  'foto', 'Foto', 1, ''),
  ('foto.kpa-g1',           'Galeri 1 — satu bidang',    'foto', 'Foto', 2, ''),
  ('foto.kpa-g2',           'Galeri 2 — musim anggaran', 'foto', 'Foto', 3, ''),
  ('foto.kpa-g3',           'Galeri 3 — traktiran',      'foto', 'Foto', 4, ''),
  ('foto.kpa-g4',           'Galeri 4 — tim inti',       'foto', 'Foto', 5, ''),
  ('foto.kpa-g5',           'Galeri 5 — dinas luar',     'foto', 'Foto', 6, ''),
  ('foto.kpa-wide',         'Foto bareng (melebar)',     'foto', 'Foto', 7, ''),

  ('stiker.street',  'Jalan di Brooklyn',      'foto', 'Stiker', 1,  ''),
  ('stiker.map',     'Baca peta di salju',     'foto', 'Stiker', 2,  ''),
  ('stiker.coffee',  'Borong kopi',            'foto', 'Stiker', 3,  ''),
  ('stiker.sofa',    'Sofa oranye',            'foto', 'Stiker', 4,  ''),
  ('stiker.dino',    'Fosil dinosaurus',       'foto', 'Stiker', 5,  ''),
  ('stiker.zoo',     'Central Park Zoo',       'foto', 'Stiker', 6,  ''),
  ('stiker.yogurt',  'Yogurt di tangga',       'foto', 'Stiker', 7,  ''),
  ('stiker.empire',  'Manjat Empire State',    'foto', 'Stiker', 8,  ''),
  ('stiker.ghost',   'Hantu hijau',            'foto', 'Stiker', 9,  ''),
  ('stiker.spider',  'Spider-Tandika',         'foto', 'Stiker', 10, ''),

  ('musik.latar', 'Musik latar (diputar berulang)', 'audio', 'Musik', 1, ''),

  ('teks.galeri.1', 'Keterangan galeri 1', 'teks', 'Keterangan galeri', 1, '01 · SATU BIDANG'),
  ('teks.galeri.2', 'Keterangan galeri 2', 'teks', 'Keterangan galeri', 2, '02 · MUSIM ANGGARAN'),
  ('teks.galeri.3', 'Keterangan galeri 3', 'teks', 'Keterangan galeri', 3, '03 · TRAKTIRAN'),
  ('teks.galeri.4', 'Keterangan galeri 4', 'teks', 'Keterangan galeri', 4, '04 · TIM INTI'),
  ('teks.galeri.5', 'Keterangan galeri 5', 'teks', 'Keterangan galeri', 5, '05 · DINAS LUAR'),
  ('teks.galeri.wide.judul', 'Judul foto melebar',       'teks', 'Keterangan galeri', 6, 'Koleksi terbaik satu bidang.'),
  ('teks.galeri.wide.label', 'Label kecil foto melebar', 'teks', 'Keterangan galeri', 7, 'TOP COLLECTION'),

  ('teks.rekening.bank',  'Nama bank / kas', 'teks', 'Rekening patungan', 1, 'KAS PELEPASAN BIDANG KPA'),
  ('teks.rekening.nomor', 'Nomor rekening',  'teks', 'Rekening patungan', 2, ''),
  ('teks.rekening.nama',  'Atas nama',       'teks', 'Rekening patungan', 3, 'Bendahara Bidang'),

  ('teks.rundown.status',  'Label status rundown (kosongkan kalau sudah fix)', 'teks', 'Rundown', 1, 'DRAFT'),
  ('teks.rundown.catatan', 'Catatan di bawah rundown (boleh dikosongkan)',     'teks', 'Rundown', 2, '*Masih draft — kabari kalau ada yang mau digeser.'),

  ('teks.profil.bio',     'Paragraf perkenalan',                  'teks', 'Teks halaman', 1, 'Kawan sebidang kita segera terbang ke New York untuk lanjut studi. Sebelum berangkat, kami satu bidang nitip kesan, harapan, dan doa di kartu ini.'),
  ('teks.profil.catatan', 'Catatan tulisan tangan di bawah jam',  'teks', 'Teks halaman', 2, 'beda 11 jam — inget itu pas nanti janjian nelpon');

insert into public.rundown (waktu, judul, catatan, urutan) values
  ('08.00', 'Kumpul & sarapan bareng',    'Patungan nasi kuning, gelar tikar',  1),
  ('09.00', 'Sesi kesan & harapan',       'Ucapan dari halaman ini dibacakan',  2),
  ('10.00', 'Games murah meriah',         'Hadiah receh, gengsi dipertaruhkan', 3),
  ('11.00', 'Serah kenang-kenangan',      'Plus foto bareng satu bidang',       4),
  ('12.00', 'Bubar, sampai jumpa di NYC', 'Yang mau lanjut, terserah',          5);


-- =============================================================
-- 7. Langkah manual yang TIDAK bisa dilakukan lewat SQL
-- =============================================================
-- 1. Buat akun admin: Authentication > Users > Add user, centang
--    "Auto Confirm User".
--
-- 2. Daftarkan akun itu sebagai admin (mengangkat satu-satunya akun yang ada,
--    jadi tidak perlu menyalin user id):
--
--      insert into public.admins (user_id, catatan)
--      select id, 'admin pertama' from auth.users order by created_at limit 1
--      on conflict (user_id) do nothing;
--
-- 3. Matikan pendaftaran publik: Authentication > Sign In / Providers >
--    nonaktifkan "Allow new users to sign up".
--
-- 4. Salin URL projek dan publishable key ke SB / SB_KEY di
--    "Pelepasan Tandika.dc.html" dan admin.html.
