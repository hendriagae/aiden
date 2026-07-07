# AIDEN EA — Setup Guide
## Adaptive Intelligence Driven Execution Node v1.0
### Instrument: XAUUSD (Gold) | Platform: MT5

---

## STEP 1: Install EA ke MT5

1. Buka MT5
2. Klik menu **File → Open Data Folder**
3. Masuk ke folder: `MQL5 → Experts`
4. Copy file `AIDEN_EA.mq5` ke folder tersebut
5. Kembali ke MT5, buka **Navigator** (Ctrl+N)
6. Klik kanan pada **Expert Advisors** → Refresh
7. AIDEN EA akan muncul di list

---

## STEP 2: Compile EA

1. Di Navigator, double-click `AIDEN_EA`
2. MetaEditor akan terbuka
3. Tekan **F7** untuk compile
4. Pastikan tidak ada error (hanya warnings yang ok)


## PENTING: JANGAN DIUBAH SAAT BOT BERJALAN

Biarkan bot bekerja. Jangan:
- ❌ Close trade manual kecuali emergency
- ❌ Override SL/TP yang sudah di-set
- ❌ Matikan bot saat ada posisi terbuka
- ❌ Ubah lot size manual

Kalau bot PAUSE karena 5 loss streak:
1. Cek kondisi market secara keseluruhan
2. Apakah ada news besar yang terlewat?
3. Apakah market sedang dalam kondisi abnormal?
4. Kalau sudah normal: reset dengan klik kanan EA → Remove, lalu load ulang

---

## TESTING DULU DI DEMO

**WAJIB demo minimal 2-4 minggu sebelum live.**

Checklist sebelum live:
- [ ] EA berjalan tanpa error
- [ ] Risk management bekerja benar (cek lot size per trade)
- [ ] Session filter aktif (bot idle di luar jam)
- [ ] Minimal 20 trade di demo sudah terjadi

---

*AIDEN v1.0 — Built for discipline, not perfection.*
