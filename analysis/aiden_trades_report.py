#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AIDEN 0.7.2 - Rapor Trade Fase 3
=================================
Membaca CSV trade log AIDEN_072.mq5, memasangkan ENTRY-EXIT
per position id, lalu menghitung statistik dalam satuan R
(risiko awal per trade).

Gerbang Fase 3: expectancy R harus POSITIF setelah semua biaya
(spread/swap/komisi sudah termakan di profit tester).

Pemakaian:
    python aiden_trades_report.py AIDEN072_trades_XAUUSD_PERIOD_M15.csv
"""

import argparse
import sys

import numpy as np
import pandas as pd


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    args = ap.parse_args()

    df = pd.read_csv(args.csv)
    df["time"] = pd.to_datetime(df["time"], format="%Y.%m.%d %H:%M:%S",
                                errors="coerce")

    ent = df[df["type"] == "ENTRY"].copy()
    ext = df[df["type"] == "EXIT"].copy()

    if ent.empty or ext.empty:
        sys.exit("Tidak ada pasangan ENTRY/EXIT di log.")

    # skema kolom (lihat header logger AIDEN_072):
    # ENTRY: posid, dir, price, sl, tp, lots, risk_money, er_slow, pb_depth
    # EXIT : posid, price=profit, sl=balance
    e = ent[["posid", "time", "dir", "price", "sl", "tp", "lots",
             "risk_money", "er_slow", "pb_depth"]].rename(
        columns={"time": "t_in"})

    x = ext[["posid", "time", "price", "sl"]].rename(
        columns={"time": "t_out", "price": "profit", "sl": "balance"})

    tr = e.merge(x, on="posid", how="inner")

    tr["profit"] = pd.to_numeric(tr["profit"], errors="coerce")
    tr["risk_money"] = pd.to_numeric(tr["risk_money"], errors="coerce")
    tr = tr.dropna(subset=["profit", "risk_money"])
    tr = tr[tr["risk_money"] > 0]

    tr["R"] = tr["profit"] / tr["risk_money"]
    tr["year"] = tr["t_in"].dt.year
    tr["hold_h"] = (tr["t_out"] - tr["t_in"]).dt.total_seconds() / 3600

    n = len(tr)
    wins = tr[tr["R"] > 0]
    loss = tr[tr["R"] <= 0]
    wr = 100 * len(wins) / n
    exp_r = tr["R"].mean()
    pf = (wins["profit"].sum() /
          abs(loss["profit"].sum())) if len(loss) else np.inf

    # drawdown kumulatif dalam R
    eq = tr.sort_values("t_in")["R"].cumsum()
    dd = (eq - eq.cummax()).min()

    print("=" * 60)
    print("RAPOR AIDEN 0.7.2 (satuan R, sudah termasuk semua biaya)")
    print("=" * 60)
    print(f"Jumlah trade     : {n}")
    print(f"Periode          : {tr['t_in'].min()} -> {tr['t_out'].max()}")
    print(f"Win rate         : {wr:.1f}%")
    print(f"Rata-rata win    : {wins['R'].mean():+.2f} R")
    print(f"Rata-rata loss   : {loss['R'].mean():+.2f} R"
          if len(loss) else "Rata-rata loss   : -")
    print(f"EXPECTANCY       : {exp_r:+.3f} R / trade")
    print(f"Profit factor    : {pf:.2f}")
    print(f"Max drawdown     : {dd:.1f} R")
    print(f"Total            : {tr['R'].sum():+.1f} R")
    print(f"Rata-rata hold   : {tr['hold_h'].mean():.1f} jam")

    print("\n-- per tahun --")
    g = tr.groupby("year").agg(n=("R", "size"), wr=("R", lambda s:
        100 * (s > 0).mean()), expR=("R", "mean"), totR=("R", "sum"))
    print(g.round(3).to_string())

    print("\n-- distribusi R --")
    print(tr["R"].describe().round(3).to_string())

    if exp_r > 0:
        print("\nGERBANG FASE 3: LULUS sementara - expectancy positif "
              "setelah biaya.\nLangkah lanjut: forward test / Fase 4 "
              "(adu manajemen).")
    else:
        print("\nGERBANG FASE 3: BELUM LULUS - expectancy <= 0.\n"
              "Kembali ke sensor/eksekusi, JANGAN menambah filter "
              "tanpa bukti.")


if __name__ == "__main__":
    main()
