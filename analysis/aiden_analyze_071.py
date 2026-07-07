#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AIDEN 0.7.1 - Timbangan Fase 2 : TANGGA KONDISI
================================================
Membaca CSV hasil AIDEN_071.mq5 dan menguji hipotesis inti:

  "trend harian + struktur searah + pullback selesai"
  harus LEBIH BAIK daripada "trend harian saja".

Setiap anak tangga menambah SATU sensor. Sensor yang tidak
menggerakkan angka dibanding tangga di bawahnya = tidak membawa
informasi baru = kandidat pangkas.

Tangga (arah selalu = dir_slow):
  A  SEMUA bar berarah           (baseline pasar)
  B  A + ER-Slow >= 30           (Sensor 1 - trend harian, sudah lulus)
  C  B + struktur searah         (Sensor 2 menambah apa?)
  D  B + pullback 20-60%         (Sensor 3a menambah apa?)
  E  D + recovery = 1            (Sensor 3b menambah apa?)
  F  C + D + E gabungan penuh    (setup lengkap AIDEN)

Metrik @ horizon 40 & 80 bar, satuan ATR:
  n, %bar, fwd_med, mfe, mae, edge (mfe/mae)

Juga dicetak: rincian band kedalaman pullback di dalam B,
dan efek recovery di dalam band sehat.

Pemakaian:
    python aiden_analyze_071.py AIDEN071_XAUUSD_PERIOD_M15.csv
"""

import argparse
import sys

import numpy as np
import pandas as pd
from numpy.lib.stride_tricks import sliding_window_view

HORIZONS = [40, 80]
TREND_TH = 30.0     # ER-Slow: hasil kalibrasi Fase 2 sebelumnya
PB_LO, PB_HI = 20.0, 60.0   # band "sehat" awal [UNCAL - diadili di sini]


def load_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)

    need = {"time", "high", "low", "close", "atr",
            "er_slow", "dir_slow", "struct_state",
            "pb_depth", "pb_recov"}
    missing = need - set(df.columns)
    if missing:
        sys.exit(f"Kolom hilang: {sorted(missing)} - "
                 f"pastikan CSV berasal dari AIDEN_071.mq5 (bukan 0.7.0)")

    df["time"] = pd.to_datetime(df["time"], format="%Y.%m.%d %H:%M:%S",
                                errors="coerce")
    df = (df.dropna(subset=["time"])
            .drop_duplicates(subset="time", keep="last")
            .sort_values("time")
            .reset_index(drop=True))

    print(f"Baris dipakai : {len(df)}")
    print(f"Rentang       : {df['time'].iloc[0]} -> {df['time'].iloc[-1]}")

    if len(df) < 2000:
        print("[PERINGATAN] Data tipis untuk tangga bertingkat - "
              "bucket dalam bisa kekurangan sampel.")

    return df


def forward(df: pd.DataFrame, h: int):
    high = df["high"].to_numpy(float)
    low = df["low"].to_numpy(float)
    close = df["close"].to_numpy(float)
    n = len(close)

    fh = np.full(n, np.nan)
    fl = np.full(n, np.nan)
    fc = np.full(n, np.nan)

    if n > h:
        wh = sliding_window_view(high, h)
        wl = sliding_window_view(low, h)
        fh[: n - h] = wh[1:].max(axis=1)
        fl[: n - h] = wl[1:].min(axis=1)
        fc[: n - h] = close[h:]

    return fh, fl, fc


def metrics(df, mask, d, fwd, mfe, mae, label, total):
    m = mask & np.isfinite(fwd) & np.isfinite(mfe) & np.isfinite(mae)
    k = int(m.sum())
    if k == 0:
        return {"kondisi": label, "n": 0, "pct": 0.0,
                "fwd_med": np.nan, "mfe": np.nan,
                "mae": np.nan, "edge": np.nan}
    return {
        "kondisi": label,
        "n": k,
        "pct": round(100.0 * k / total, 2),
        "fwd_med": round(float(np.median(fwd[m])), 3),
        "mfe": round(float(np.mean(mfe[m])), 3),
        "mae": round(float(np.mean(mae[m])), 3),
        "edge": round(float(np.mean(mfe[m]) / np.mean(mae[m])), 3),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="AIDEN 0.7.1 tangga kondisi")
    ap.add_argument("csv")
    ap.add_argument("--out", default="aiden_ladder_summary.csv")
    args = ap.parse_args()

    df = load_csv(args.csv)

    atr = df["atr"].to_numpy(float)
    close = df["close"].to_numpy(float)
    d = df["dir_slow"].to_numpy(float)
    er_s = df["er_slow"].to_numpy(float)
    st = df["struct_state"].to_numpy(float)
    pbd = df["pb_depth"].to_numpy(float)
    pbr = df["pb_recov"].to_numpy(float)

    base_valid = (d != 0) & (atr > 0) & (er_s >= 0)

    all_rows = []

    for h in HORIZONS:
        fh, fl, fc = forward(df, h)

        with np.errstate(invalid="ignore", divide="ignore"):
            fwd = d * (fc - close) / atr
            mfe = np.where(d > 0, (fh - close) / atr, (close - fl) / atr)
            mae = np.where(d > 0, (close - fl) / atr, (fh - close) / atr)

        A = base_valid
        B = A & (er_s >= TREND_TH)
        C = B & (st == d)
        D = B & (pbd >= PB_LO) & (pbd <= PB_HI)
        E = D & (pbr == 1)
        F = C & D & (pbr == 1)

        total = int(A.sum())

        rows = [
            metrics(df, A, d, fwd, mfe, mae, "A  semua berarah", total),
            metrics(df, B, d, fwd, mfe, mae,
                    f"B  + ER-Slow>={TREND_TH:.0f}", total),
            metrics(df, C, d, fwd, mfe, mae, "C  B + struktur searah", total),
            metrics(df, D, d, fwd, mfe, mae,
                    f"D  B + pullback {PB_LO:.0f}-{PB_HI:.0f}%", total),
            metrics(df, E, d, fwd, mfe, mae, "E  D + recovery", total),
            metrics(df, F, d, fwd, mfe, mae, "F  C+D+recovery (full)", total),
        ]

        tab = pd.DataFrame(rows)
        print("\n" + "=" * 70)
        print(f"TANGGA KONDISI | horizon = {h} bar | satuan ATR")
        print("=" * 70)
        print(tab.to_string(index=False))

        tab.insert(0, "horizon", h)
        all_rows.append(tab)

        # --- rincian band kedalaman pullback di dalam B
        bands = [0, 10, 20, 30, 40, 50, 60, 80, 100, 1000]
        names = ["0-10", "10-20", "20-30", "30-40", "40-50",
                 "50-60", "60-80", "80-100", ">100"]
        det = []
        for lo, hi, nm in zip(bands[:-1], bands[1:], names):
            m = B & (pbd >= lo) & (pbd < hi)
            det.append(metrics(df, m, d, fwd, mfe, mae, nm, total))
        dtab = pd.DataFrame(det)
        print(f"\n-- kedalaman pullback di dalam B (h={h}) --")
        print(dtab.to_string(index=False))

        # --- efek recovery di band sehat
        m_band = B & (pbd >= PB_LO) & (pbd <= PB_HI)
        rec = [
            metrics(df, m_band & (pbr == 1), d, fwd, mfe, mae,
                    "recovery = 1", total),
            metrics(df, m_band & (pbr == 0), d, fwd, mfe, mae,
                    "recovery = 0", total),
        ]
        rtab = pd.DataFrame(rec)
        print(f"\n-- efek recovery di band {PB_LO:.0f}-{PB_HI:.0f}% "
              f"(h={h}) --")
        print(rtab.to_string(index=False))

    pd.concat(all_rows, ignore_index=True).to_csv(args.out, index=False)
    print(f"\nRingkasan tersimpan: {args.out}")

    print("""
CARA MEMBACA
------------
1. Bandingkan tiap anak tangga dengan B. Sensor layak hidup hanya
   jika fwd_med / edge naik BERARTI dibanding B - bukan sekadar
   beda tipis dengan n yang menyusut drastis.
2. Tabel kedalaman menunjukkan di mana pullback "sehat" SEBENARNYA
   berada menurut data - band 20-60% hanyalah hipotesis awal.
3. Recovery yang jujur harus memisahkan kedua barisnya dengan jelas.
4. n kecil (< ~200) = tahan diri dari kesimpulan.
""")


if __name__ == "__main__":
    main()
