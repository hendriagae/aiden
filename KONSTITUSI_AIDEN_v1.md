# KONSTITUSI AIDEN v1.0

*Disahkan 4 Juli 2026, menutup fase riset 0.6.1 → 0.7.5, membuka fase forward test.*
*Dokumen ini membekukan filosofi AIDEN. Perubahan apa pun harus melalui mekanisme Pasal 5.*

---

## MUKADIMAH — Identitas

AIDEN adalah sistem pengambilan keputusan yang membaca struktur pasar, mengikuti
tren skala harian yang terbukti valid, masuk pada koreksi yang sehat, lalu
mengelola posisi berdasarkan satu pertanyaan — *"apakah alasan saya masuk masih
berlaku?"* — hingga jawabannya tidak.

AIDEN **bukan** peramal harga, **bukan** sistem yang menyesuaikan dirinya sendiri,
dan **bukan** mesin gaji bulanan. AIDEN adalah **pemanen rezim**: panen besar saat
pasar trending, bertahan hidup saat pasar mati. Kemampuan mengikuti zaman tidak
tinggal di kodenya, melainkan di proses yang menaunginya (Pasal 6–7).

---

## PASAL 1 — Lima Pertanyaan (Filosofi Beku)

| # | Pertanyaan | Implementasi 0.7.5 | Status pengadilan |
|---|---|---|---|
| 1 | Apakah market sedang trend? | ER-Slow(48) ≥ 30, arah = tanda netto | LULUS (hidup 2 dari 3 era) |
| 2 | Apakah trend cukup sehat? | Melebur ke magnitudo ER | Komposit terpisah DIPANGKAS |
| 3 | Apakah sedang pullback? | Depth 20–40% dari impuls 20 bar | LULUS BERSYARAT (kuat 1 era, netral 2) |
| 4 | Apakah pullback selesai? | **Sengaja tidak ditanya** — entry di dalam zona | Konfirmasi DITOLAK data (−0.4R) |
| 5 | Apakah alasan masih berlaku? | Mode ADAPTIVE (Pasal 3) | JUARA DUEL (+58R vs +47R) |

---

## PASAL 2 — Amandemen Hasil Pengadilan Data

1. **SwingStructure (HH/HL)** tidak membawa informasi baru di atas ER →
   diturunkan dari filter keputusan menjadi **infrastruktur** (penentu level SL).
2. **Recovery candle / konfirmasi** memperburuk hasil → entry dilakukan
   *di dalam* zona pullback, bukan setelah bukti pembalikan.
3. Komposit **Confidence / Opportunity / Strength** = informasi yang sama
   dikemas ulang → dilarang hidup kembali tanpa lulus tangga kondisi.
4. Kontinuasi XAUUSD hidup di **horizon 40–80 bar M15** (10–20 jam);
   horizon 5–20 bar tidak punya edge dan cenderung berbalik.
5. Kata **"adaptif"** hanya sah untuk manajemen posisi, bukan untuk sistem.

---

## PASAL 3 — Manajemen Posisi (Mode ADAPTIVE)

- Tanpa take profit. Posisi hidup selama alasannya hidup.
- **PROTECT**: SL awal di level invalidasi depth 65% + buffer 0.2 ATR.
- **EXPAND/LOCK**: setelah struktur melewati harga entry, SL trail di bawah
  low struktur 20 bar (mirror untuk short). Tidak pernah mundur.
- **EXIT**: trend mati (ER-Slow < 20) ATAU trend berbalik (ER ≥ 30 lawan arah)
  ATAU backstop 160 bar.
- Risiko: 1% per trade, dihitung via OrderCalcProfit. Daily loss limit 3%.
  Satu posisi per simbol. Tanpa cooldown.

---

## PASAL 4 — Register Parameter & Akta Kelahiran

| Parameter | Nilai | Akta |
|---|---|---|
| ER_WindowSlow | 48 bar | Fase 2: horizon kontinuasi 40–80 bar |
| TrendThreshold | 30 | Persentil tabel ER, tervalidasi 2/3 era |
| PB_Min–PB_Max | 20–40% | Zona edge era kalibrasi; LEMAH lintas era |
| PB_InvalidDepth | 65% | Zona 60–80% = trend mati (tabel depth) |
| RegimeExitER | 20 | Standing rule; tugas: deklarasi trend mati |
| MaxHoldBars (dumb/adapt) | 80 / 160 | 1× / 2× horizon kalibrasi |
| SL_BufferATR, MinSL, MaxSL | 0.2 / 0.5 / 3.0 ATR | [UNCAL] — pagar teknis |
| RiskPercent | 1% | Keputusan risiko, bukan hasil kalibrasi |

Parameter [UNCAL] tidak boleh dioptimasi diam-diam; perubahan = Pasal 5.

---

## PASAL 5 — Aturan Penerimaan Fitur

Fitur, filter, sensor, atau parameter baru hanya boleh masuk jika:
1. Diajukan sebagai **hipotesis tertulis sebelum melihat hasilnya**;
2. Lulus **tangga kondisi** (menaikkan fwd_med/edge secara berarti di atas
   kondisi tanpa fitur itu, bukan sekadar beda tipis dengan n menyusut);
3. Tervalidasi di **minimal 2 dari 3 era** ATAU di data yang belum pernah
   dipakai untuk merumuskannya;
4. Menang/imbang dalam **backtest EA tiga era** melawan versi tanpa fitur.

Argumen yang meyakinkan bukan bukti. COMPLETE state, Opportunity ≥ 55, dan
recovery candle semuanya meyakinkan — dan semuanya mati di pengadilan.

---

## PASAL 6 — Protokol Kematian (ditulis sebelum perang, bukan saat panik)

Forward test / live DIHENTIKAN SEMENTARA (pause entry baru, posisi berjalan
dikelola sampai selesai) jika salah satu terjadi:
- **Expectancy bergulir 60 trade < −0.15R**, atau
- **Drawdown melebihi 30R** dari puncak equity, atau
- **12 bulan kumulatif negatif** berturut-turut.

DIHENTIKAN TOTAL + audit sebelum satu trade berikutnya jika:
- Loss tunggal melebihi **1.5R tanpa gap harga** (indikasi bug sizing/SL), atau
- Perilaku menyimpang dari desain (entry di luar kondisi, SL tidak terpasang).

Setelah pause: kembali ke pengadilan Fase 2 pada data terbaru. AIDEN hanya
boleh hidup lagi jika lulus ulang. Semua sistem akhirnya mati; konstitusi ini
memastikan AIDEN mati dengan murah dan terhormat.

---

## PASAL 7 — Ritual Rekalibrasi & Ekspansi

1. **Tiap 6 bulan**: jalankan ulang tangga kondisi pada jendela data bergulir.
   Parameter harus tetap di pita stabilnya; pergeseran besar = sidang ulang penuh.
2. **Instrumen baru** (XAGUSD, dst.) wajib melewati jalurnya sendiri:
   logger → tangga kondisi 3 era → kalibrasi sendiri → EA backtest → duel →
   baru bergabung ke portofolio. Threshold TIDAK diwariskan antar instrumen.
3. **Timeframe** tidak diturunkan tanpa pengadilan biaya-masuk (spread sebagai
   % risiko wajib dihitung dalam tangga kondisinya).

---

## PASAL 8 — Ekspektasi Resmi (agar tidak ada kejutan yang pura-pura kaget)

- ±10 trade/bulan (6–15); tidak ada bulan kosong dalam 72 bulan uji.
- Win rate 32–40%; loss rata-rata ≈ −0.6R; nafkah datang dari ekor kanan
  (trade +3R sampai +16R yang langka).
- Rata-rata ≈ +0.5–0.8R/bulan ≈ 7–10%/tahun pada risk 1%.
- Hanya ±54% bulan positif; kekeringan hingga 4 bulan; tahun datar itu normal.
- Drawdown terburuk teruji ≈ 26R. Menaikkan risk menggandakan ini.
- AIDEN menumbuhkan modal; ia bukan gaji. VPS/infrastruktur = biaya tetap
  dari kantong, bukan dari ekspektasi profit.

---

## RIWAYAT SINGKAT

0.6.1 indikator 15-engine (audit: Direction berlantai 50, trigger lumpuh, state
hantu) → 0.7.0 rebuild: sensor lahir bersama timbangan → 0.7.1 pengadilan
S2/S3 → 0.7.2 EA pertama → 0.7.3 fix lot sizing 10× (OrderCalcProfit) →
0.7.4 duel manajemen: ADAPTIVE juara (+58R vs +47R, 6 tahun, 3 era, termasuk
runner +16R Okt 2023) → 0.7.5 observabilitas, berangkat forward test.

*Prinsip yang menaungi semuanya: tidak ada angka tanpa akta kelahiran,
tidak ada fitur tanpa pengadilan, tidak ada kematian tanpa protokol.*
