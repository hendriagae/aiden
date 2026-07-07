#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AIDEN 0.7 - Timbangan Fase 2
============================
Membaca CSV hasil logger AIDEN_07.mq5 dan mengukur apakah Sensor 1
(TrendEfficiency) benar-benar punya daya prediksi terhadap pergerakan
ke depan, atau hanya label tanpa makna.

Pertanyaan yang dijawab skrip ini, dengan angka:
  "Ketika ER tinggi + arah jelas, apakah distribusi pergerakan
   10-20 bar berikutnya BERBEDA dari saat ER rendah?"

Metrik per bucket ER (0-10, 10-20, ..., 90-100):
  n         : jumlah bar dalam bucket
  fwd_med   : median return searah-trend H bar ke depan, satuan ATR
              (positif = harga melanjut searah sensor)
  mfe_mean  : rata-rata Maximum Favorable Excursion (ATR) dalam H bar
  mae_mean  : rata-rata Maximum Adverse Excursion (ATR) dalam H bar
  edge      : mfe_mean / mae_mean  (>1 berarti ruang profit rata-rata
              lebih besar dari ruang sakitnya)

Kalau angka-angka itu datar di semua bucket -> sensor tidak membawa
informasi, dan kita berhemat berbulan-bulan.

Pemakaian:
    python aiden_analyze.py AIDEN07_XAUUSD_PERIOD_M15.csv
    python aiden_analyze.py file.csv --horizons 5 10 20

Dependensi: pandas, numpy   (pip install pandas numpy)
"""

import argparse
import sys

import numpy as np
import pandas as pd
from numpy.lib.stride_tricks import sliding_window_view

VARIANTS = [
    ("fast", "er_fast", "dir_fast"),
    ("mid",  "er_mid",  "dir_mid"),
    ("slow", "er_slow", "dir_slow"),
]

ER_BINS = list(range(0, 101, 10))  # 0-10, 10-20, ..., 90-100


# ------------------------------------------------------------------
# Muat & bersihkan data
# ------------------------------------------------------------------

def load_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)

    required = {"time", "open", "high", "low", "close", "atr"} | {
        c for _, e, d in VARIANTS for c in (e, d)
    }
    missing = required - set(df.columns)
    if missing:
        sys.exit(f"Kolom hilang di CSV: {sorted(missing)} "
                 f"- pastikan file berasal dari AIDEN_07.mq5")

    df["time"] = pd.to_datetime(df["time"], format="%Y.%m.%d %H:%M:%S",
                                errors="coerce")
    df = df.dropna(subset=["time"])

    # Logger bisa menulis duplikat saat indikator di-restart -> dedup.
    before = len(df)
    df = (df.drop_duplicates(subset="time", keep="last")
            .sort_values("time")
            .reset_index(drop=True))
    dupes = before - len(df)

    print(f"Baris dimuat   : {before}")
    print(f"Duplikat dibuang: {dupes}")
    print(f"Baris dipakai  : {len(df)}")
    print(f"Rentang waktu  : {df['time'].iloc[0]}  ->  {df['time'].iloc[-1]}")

    if len(df) < 500:
        print("\n[PERINGATAN] Data < 500 bar. Kesimpulan statistik "
              "belum layak dipercaya - kumpulkan lebih banyak "
              "(jalankan indikator di Strategy Tester atas data historis).")

    return df


# ------------------------------------------------------------------
# Ekstrem ke depan (untuk MFE/MAE) tanpa look-ahead ke bar sendiri:
# jendela mencakup bar t+1 .. t+H
# ------------------------------------------------------------------

def forward_arrays(high: np.ndarray, low: np.ndarray,
                   close: np.ndarray, h: int):
    n = len(close)
    fwd_high = np.full(n, np.nan)
    fwd_low = np.full(n, np.nan)
    fwd_close = np.full(n, np.nan)

    if n > h:
        wh = sliding_window_view(high, h)   # baris i = window [i, i+h-1]
        wl = sliding_window_view(low, h)
        fwd_high[: n - h] = wh[1:].max(axis=1)   # window mulai di i+1
        fwd_low[: n - h] = wl[1:].min(axis=1)
        fwd_close[: n - h] = close[h:]

    return fwd_high, fwd_low, fwd_close


# ------------------------------------------------------------------
# Analisis satu variasi sensor x satu horizon
# ------------------------------------------------------------------

def analyze(df: pd.DataFrame, er_col: str, dir_col: str,
            horizon: int) -> pd.DataFrame:
    high = df["high"].to_numpy(float)
    low = df["low"].to_numpy(float)
    close = df["close"].to_numpy(float)
    atr = df["atr"].to_numpy(float)
    er = df[er_col].to_numpy(float)
    d = df[dir_col].to_numpy(float)

    fwd_high, fwd_low, fwd_close = forward_arrays(high, low, close, horizon)

    # return searah-trend, dinormalisasi ATR
    with np.errstate(invalid="ignore", divide="ignore"):
        fwd_ret = d * (fwd_close - close) / atr
        mfe = np.where(d > 0, (fwd_high - close) / atr,
                       np.where(d < 0, (close - fwd_low) / atr, np.nan))
        mae = np.where(d > 0, (close - fwd_low) / atr,
                       np.where(d < 0, (fwd_high - close) / atr, np.nan))

    valid = (
        (er >= 0) & (d != 0) & (atr > 0)
        & np.isfinite(fwd_ret) & np.isfinite(mfe) & np.isfinite(mae)
    )

    sub = pd.DataFrame({
        "er": np.clip(er[valid], 0, 99.999),
        "fwd": fwd_ret[valid],
        "mfe": mfe[valid],
        "mae": mae[valid],
    })

    if sub.empty:
        return pd.DataFrame()

    sub["bucket"] = pd.cut(sub["er"], bins=ER_BINS, right=False)

    g = sub.groupby("bucket", observed=True).agg(
        n=("fwd", "size"),
        fwd_med=("fwd", "median"),
        fwd_mean=("fwd", "mean"),
        mfe_mean=("mfe", "mean"),
        mae_mean=("mae", "mean"),
    )
    g["edge"] = g["mfe_mean"] / g["mae_mean"]

    # baseline tanpa kondisi apa pun - pembanding jujur
    base = pd.DataFrame({
        "n": [len(sub)],
        "fwd_med": [sub["fwd"].median()],
        "fwd_mean": [sub["fwd"].mean()],
        "mfe_mean": [sub["mfe"].mean()],
        "mae_mean": [sub["mae"].mean()],
    }, index=["SEMUA (baseline)"])
    base["edge"] = base["mfe_mean"] / base["mae_mean"]

    return pd.concat([g, base])


# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description="AIDEN 0.7 Fase-2 analyzer")
    ap.add_argument("csv", help="File CSV hasil AIDEN_07.mq5")
    ap.add_argument("--horizons", type=int, nargs="+", default=[5, 10, 20],
                    help="Horizon forward dalam bar (default: 5 10 20)")
    ap.add_argument("--out", default="aiden_summary.csv",
                    help="File ringkasan keluaran")
    args = ap.parse_args()

    df = load_csv(args.csv)

    all_rows = []

    for name, er_col, dir_col in VARIANTS:
        for h in args.horizons:
            res = analyze(df, er_col, dir_col, h)
            if res.empty:
                continue

            print("\n" + "=" * 68)
            print(f"SENSOR ER-{name.upper()}  |  horizon = {h} bar  "
                  f"(satuan: ATR)")
            print("=" * 68)
            print(res.round(3).to_string())

            res = res.reset_index(names="bucket")
            res.insert(0, "horizon", h)
            res.insert(0, "variant", name)
            all_rows.append(res)

    if not all_rows:
        sys.exit("Tidak ada data valid untuk dianalisis.")

    summary = pd.concat(all_rows, ignore_index=True)
    summary.to_csv(args.out, index=False)
    print(f"\nRingkasan tersimpan: {args.out}")

    print("""
CARA MEMBACA HASIL
------------------
1. Lihat kolom fwd_med dari bucket rendah ke tinggi. Sensor yang
   sehat menunjukkan tren menaik: ER tinggi -> kelanjutan searah
   lebih besar. Kalau datar/acak -> sensor tidak membawa informasi.
2. Kolom edge (MFE/MAE): bucket dengan edge jelas > baseline adalah
   kandidat zona threshold. Threshold final ditarik DARI SINI,
   bukan dari selera.
3. Bandingkan fast/mid/slow: jendela dengan pemisahan antar-bucket
   paling tegas adalah jendela yang layak dipakai.
4. n kecil (< ~100) per bucket = jangan ditarik kesimpulan dulu.
""")


if __name__ == "__main__":
    main()
