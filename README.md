# Pelepasan Tandika

Kartu pelepasan digital untuk Tandika Nisaa Utami — Bidang KPA.
Acara: Minggu, 23 Agustus 2026 · 08:00 WIB · Anjungan Sulawesi, TMII.

Halaman statis satu file, tanpa framework dan tanpa dependency.
Ucapan disimpan di Supabase.

## Kenapa Supabase, bukan Firebase

Halaman ini satu file HTML statis tanpa bundler. Supabase dipakai lewat
`fetch()` biasa — nol dependency, nol build step untuk sisi datanya.
Firebase butuh SDK-nya di-import, dan runtime `.dc.html` ini sudah
memuat React lewat `support.js`, jadi menambah module loader cuma
menambah bagian yang bisa rusak tanpa keuntungan setimpal.

## Struktur

```
Pelepasan Tandika.dc.html   halaman (sumber kebenaran, nama sengaja dipertahankan)
admin.html                  panel admin — foto, teks, moderasi ucapan
support.js                  runtime .dc.html
image-slot.js               web component slot foto
assets/                     cadangan stiker + musik (opsional — lihat catatan)
build.js                    salin semuanya ke dist/, halaman jadi index.html
serve.js                    server statis lokal untuk mencoba hasil build
vercel.json                 konfigurasi deploy
```

## Jalankan lokal

```bash
node build.js && node serve.js
```

Buka http://localhost:4321

## Deploy ke Vercel

```bash
npx vercel --prod
```

`vercel.json` sudah mengatur `buildCommand: node build.js` dan
`outputDirectory: dist`. Tidak ada dependency, jadi install step-nya kosong.
Tidak ada environment variable yang perlu diisi — publishable key Supabase
memang aman berada di kode klien (lihat bagian keamanan).

## Panel admin

Ada di `/admin.html` — misalnya `https://namamu.vercel.app/admin.html`.
Halamannya publik tapi seluruh isinya di balik login, dan sudah diberi
`noindex` supaya tidak muncul di Google.

Yang bisa diatur tanpa menyentuh kode:

- **Foto** — 7 slot (potret Tandika, galeri 1–5, foto melebar).
- **Stiker** — 10 stiker ilustrasi. Sekali unggah berlaku untuk semua
  pemakaiannya; spider, empire, dan zoo masing-masing muncul dua kali.
- **Musik** — lagu latar yang diputar berulang, lengkap dengan pemutar
  pratinjau di panel supaya bisa dicek sebelum dipakai.
- **Teks** — keterangan galeri, nomor rekening + atas nama, paragraf
  perkenalan, catatan tulisan tangan di bawah jam.
- **Ucapan** — lihat semuanya dan hapus yang tidak pantas. Ini penting
  karena ucapannya dibacakan di depan orang banyak.

Gambar otomatis dikecilkan sampai maksimal 1600px sebelum dikirim, jadi
halaman tetap ringan dibuka pakai data seluler. Format keluarannya mengikuti
format masukan — PNG tetap PNG, bukan dipaksa jadi JPEG — karena stiker
berlatar bening dan JPEG tidak punya kanal alpha sama sekali. Berkas lama
ikut terhapus dari penyimpanan waktu diganti, biar kuota tidak menumpuk.
Audio dilewatkan apa adanya, batas 12 MB.

Catatan peringatan "nomor rekening masih contoh" di halaman hilang sendiri
begitu nomor asli diisi — tidak perlu diapa-apakan.

### Menyiapkan akun admin (sekali saja)

Saya sengaja tidak membuatkan akunnya: itu berarti saya menentukan kata
sandi kamu. Tiga langkah, sekitar dua menit.

1. Buka **Authentication → Users → Add user** di dashboard Supabase.
   Isi email dan kata sandi, centang **Auto Confirm User**.

2. Buka **SQL Editor**, jalankan ini. Perintahnya mengangkat satu-satunya
   akun yang ada, jadi tidak perlu menyalin user id manual:

   ```sql
   insert into public.admins (user_id, catatan)
   select id, 'admin pertama' from auth.users order by created_at limit 1
   on conflict (user_id) do nothing;
   ```

3. Buka **Authentication → Sign In / Providers**, matikan **Allow new users
   to sign up**. Tanpa ini orang asing masih bisa mendaftar sendiri. Mereka
   tetap tidak bisa mengubah apa pun (sudah saya uji), tapi tidak ada
   gunanya membiarkan pintunya terbuka.

Setelah itu buka `/admin.html` dan masuk. Kalau akunnya berhasil masuk tapi
belum terdaftar di tabel `admins`, panel akan bilang persis begitu, bukan
menampilkan halaman kosong yang membingungkan.

### Menambah kolom yang bisa diedit

Panel membangun formulirnya dari isi tabel `content`, jadi tidak perlu
mengubah kode panel. Dua langkah:

```sql
insert into public.content (key, label, kind, grp, urutan, value)
values ('teks.penutup.salam', 'Salam penutup', 'teks', 'Teks halaman', 3, 'Sampai ketemu lagi');
```

lalu di `Pelepasan Tandika.dc.html`, tambahkan nilainya di `contentVals()`
dan pakai `{{ namaNilai }}` di tempat yang diinginkan.

## Backend ucapan

Projek Supabase: `pelepasan-tandika` (`djzzayvisldfuczhqmjb`),
region ap-southeast-1 (Singapura), free tier, $0/bulan.

Tabelnya: `wishes` (ucapan), `content` (foto & teks yang bisa diedit),
`admins` (daftar putih pengelola), plus bucket penyimpanan `foto`.

`public.wishes`:

| kolom | tipe | catatan |
|---|---|---|
| `id` | uuid | primary key |
| `name` | text | 1–42 karakter, sama dengan `maxLength` di form |
| `msg` | text | 2–420 karakter |
| `att` | text | hanya `Datang` atau `Absen` |
| `owner_token` | uuid | rahasia per-perangkat, **tidak bisa dibaca publik** |
| `created_at` | timestamptz | |

Halaman melakukan polling tiap 8 detik (berhenti kalau tab tidak aktif),
jadi ucapan yang masuk dari HP lain muncul sendiri saat sesi 09.00 tanpa
perlu refresh.

### Keamanan

Halaman ini publik, jadi publishable key ikut terkirim ke browser. Itu
memang wajar — seluruh pengamanan ada di database, bukan di kerahasiaan
key. Yang berlaku sekarang:

- RLS aktif. Publik hanya boleh `SELECT` dan `INSERT`.
- Tidak ada policy `UPDATE` maupun `DELETE`, jadi keduanya selalu ditolak.
- Grant diberikan **per kolom**. `owner_token` tidak ikut di-grant, jadi
  tidak ada cara membaca token orang lain. Konsekuensinya `select=*` akan
  ditolak server — klien wajib menyebut kolomnya satu per satu.
- Penghapusan hanya lewat RPC `delete_wish(p_id, p_token)`, yang menghapus
  cuma kalau id **dan** token cocok. Token disimpan di `localStorage`
  perangkat penulis. Tombol hapus juga hanya dirender di kartu sendiri.
- Panjang dan nilai divalidasi sebagai check constraint di database, bukan
  cuma di form, jadi request langsung ke API tetap tidak bisa menitip
  data ngawur.

Untuk panel admin, pengamanannya bertingkat:

- Menulis apa pun (`content`, penyimpanan foto, hapus ucapan) mensyaratkan
  `is_admin()`, yaitu terdaftar di tabel `admins` — **bukan** sekadar
  "sudah login". Kalau signup publik kelupaan dimatikan, orang asing yang
  berhasil mendaftar tetap tidak bisa mengubah apa pun.
- Tabel `admins` tidak bisa disentuh lewat API sama sekali. Hanya lewat
  SQL Editor.
- Ini sudah diuji dengan menirukan pengguna yang sudah login tapi belum
  terdaftar: `is_admin()` balas false, 0 baris `content` berubah, 0 ucapan
  terhapus, insert dan unggah ditolak.

Security Advisor Supabase memunculkan empat catatan. Keempatnya disengaja:

| Catatan | Alasan |
|---|---|
| `delete_wish` bisa dipanggil anon | Tanpa itu tidak ada mekanisme hapus untuk penulis biasa. Parameternya bertipe `uuid` (tidak bisa disuntik SQL), `search_path` dikunci, hanya balas boolean. |
| `delete_wish` bisa dipanggil authenticated | Sama, satu fungsi terdeteksi dua kali. |
| `is_admin` bisa dipanggil authenticated | Memang harus — panel memakainya untuk memeriksa diri sendiri. Hanya balas boolean tentang si pemanggil. |
| `admins` punya RLS tanpa policy | Justru itu maksudnya: tanpa policy berarti tidak ada yang lolos lewat API. |

Yang sengaja **tidak** dipasang: rate limit. Untuk link yang disebar di
grup satu bidang, risikonya kecil. Kalau nanti linknya tersebar lebih luas
dan ada yang iseng spam, kabari — paling gampang ditambal dengan Cloudflare
Turnstile atau rate limit per IP di Edge Function.

## Catatan yang belum beres

**Stiker dan musik belum diisi.** Sepuluh stiker ilustrasi dan satu lagu
latar. Unggah lewat panel admin (tab *Foto & media*) — tidak perlu build
ulang, tidak perlu git.

Berkasnya ada di projek Claude Design tapi **tidak bisa ditarik lewat
API-nya**: batas transfernya 192 KiB per berkas, sedangkan stikernya PNG
720×720 yang semuanya lebih besar — empat sudah dicoba, semuanya berhenti
persis di 196608 byte dengan PNG rusak. Ambil manual:

1. Buka projeknya di Claude Design, cari opsi unduh/download projek.
2. Kalau tidak ada, buka pratinjaunya lalu klik kanan tiap stiker →
   **Simpan gambar sebagai**. Sepuluh kali, tapi pasti berhasil.
3. Lagunya aslinya kamu sendiri yang unggah (ada di `uploads/MYC Ke NYC.mp3`
   di projek itu), jadi kemungkinan besar masih ada di komputermu.

Setelah berkasnya ada di komputer, unggah lewat panel. Selesai.

Halaman memakai cadangan berlapis untuk stiker dan musik:

1. yang diunggah lewat panel admin — dipakai kalau ada;
2. berkas lokal di `assets/` — kalau kamu lebih suka menaruhnya di repo dan
   build ulang, jalur ini tetap jalan;
3. kalau dua-duanya tidak ada, gambarnya **disembunyikan**, bukan jadi ikon
   gambar rusak. Keterangan di bawah stiker galeri tetap kebaca.

Artinya halaman aman di-deploy sekarang juga. Ucapan, foto, rekening, dan
panel admin sama sekali tidak bergantung pada berkas-berkas ini.

**Slot foto masih kosong.** Tujuh slot foto (potret Tandika + galeri KPA)
belum ada isinya — isi lewat panel admin.

**Free tier bisa auto-pause.** Supabase mempause projek free tier yang
aktivitasnya rendah selama 7 hari, dengan email peringatan sekitar seminggu
sebelumnya. Beberapa request per hari sudah cukup untuk mencegahnya — jadi
selama ada yang mengisi ucapan menjelang hari-H, aman. Kalau halamannya
sepi lebih dari seminggu sebelum 23 Agustus, buka saja sekali biar tercatat
aktivitas. Kalau mau benar-benar aman, upgrade ke Pro.

**Nomor rekening di bagian Kenang-kenangan masih contoh** — sudah ada
catatannya sendiri di halaman.
