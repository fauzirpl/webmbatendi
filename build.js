// Build statis untuk Vercel.
//
// Sumbernya tetap "Pelepasan Tandika.dc.html" supaya file ini masih cocok
// dengan projek Claude Design (nama file di sana dipakai sebagai identitas).
// Vercel butuh index.html di root output, jadi di sini disalin saja.

const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const OUT = path.join(ROOT, 'dist');
const PAGE = 'Pelepasan Tandika.dc.html';

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });

// Halaman utama -> index.html
fs.copyFileSync(path.join(ROOT, PAGE), path.join(OUT, 'index.html'));
console.log('  index.html      <- ' + PAGE);

// Panel admin — halaman terpisah, tidak menumpang runtime .dc.html
fs.copyFileSync(path.join(ROOT, 'admin.html'), path.join(OUT, 'admin.html'));
console.log('  admin.html');

// Runtime .dc.html + web component image-slot
for (const f of ['support.js', 'image-slot.js']) {
  fs.copyFileSync(path.join(ROOT, f), path.join(OUT, f));
  console.log('  ' + f);
}

// Sidecar state image-slot, kalau ada (isi foto yang sudah di-drop)
const sidecar = '.image-slots.state.json';
if (fs.existsSync(path.join(ROOT, sidecar))) {
  fs.copyFileSync(path.join(ROOT, sidecar), path.join(OUT, sidecar));
  console.log('  ' + sidecar);
}

// Stiker + musik
const assetsSrc = path.join(ROOT, 'assets');
const assetsOut = path.join(OUT, 'assets');
fs.mkdirSync(assetsOut, { recursive: true });

// README.md di assets/ itu catatan untuk yang membaca repo, bukan berkas
// yang perlu tersaji ke pengunjung.
const files = (fs.existsSync(assetsSrc) ? fs.readdirSync(assetsSrc) : [])
  .filter(f => f.toLowerCase() !== 'readme.md');
for (const f of files) {
  fs.copyFileSync(path.join(assetsSrc, f), path.join(assetsOut, f));
}
console.log('  assets/         ' + files.length + ' file');

// Gambar kartu pratinjau tautan. Kalau hilang, tautan yang dibagikan di
// WhatsApp tampil tanpa gambar — tidak rusak, tapi jauh kurang menarik.
if (!files.includes('og.jpg')) {
  console.warn('\n  ! assets/og.jpg tidak ada — pratinjau tautan WhatsApp akan tampil tanpa gambar.');
}

// Aset ini OPSIONAL sejak stiker & musik bisa diunggah lewat panel admin.
// Kalau ada di sini, dipakai sebagai cadangan waktu panel belum diisi —
// jadi ketidakhadirannya bukan kegagalan build, cuma perlu diketahui.
const CADANGAN = [
  'stk-coffee.png', 'stk-dino.png', 'stk-empire.png', 'stk-ghost.png', 'stk-map.png',
  'stk-sofa.png', 'stk-spider.png', 'stk-street.png', 'stk-yogurt.png', 'stk-zoo.png',
  'myc-ke-nyc.mp3'
];
const kurang = CADANGAN.filter(f => !files.includes(f));
if (kurang.length === CADANGAN.length) {
  console.log('\n  Tidak ada berkas cadangan di assets/ — stiker & musik diambil');
  console.log('  dari panel admin. Yang belum diunggah di sana akan disembunyikan,');
  console.log('  bukan jadi gambar rusak.\n');
} else if (kurang.length) {
  console.log('\n  ' + (CADANGAN.length - kurang.length) + '/' + CADANGAN.length + ' berkas cadangan ada di assets/. Belum ada:');
  for (const f of kurang) console.log('      - ' + f);
  console.log('  Tidak masalah kalau yang ini diunggah lewat panel admin.\n');
} else {
  console.log('\n  Semua berkas cadangan lengkap di assets/.\n');
}
