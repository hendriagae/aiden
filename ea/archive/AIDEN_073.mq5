//+------------------------------------------------------------------+
//|                                                   AIDEN_073.mq5  |
//|                AIDEN 0.7.3 - BASELINE DUNGU (fix lot sizing)           |
//|                                                                  |
//|  FASE 3 : menguji apakah entry terkalibrasi selamat dari biaya.  |
//|                                                                  |
//|  ENTRY (semua angka berakta kelahiran - Fase 2, 46.907 bar):     |
//|    - ER-Slow(48) >= 30            -> trend skala harian          |
//|    - Pullback depth 20-40%        -> zona sehat hasil data       |
//|    - Arah = arah trend (dir_slow)                                |
//|    - Satu posisi, keputusan hanya di bar tertutup                |
//|                                                                  |
//|  MANAJEMEN (SENGAJA DUNGU - pembanding untuk Fase 4):            |
//|    - SL  : level invalidasi depth 65% (data: 60-80% = trend      |
//|            mati) + buffer ATR                                    |
//|    - TP  : tetap 1.5R                                            |
//|    - Time stop : tutup paksa setelah MaxHoldBars                 |
//|    - TANPA trailing, TANPA break-even, TANPA partial close       |
//|                                                                  |
//|  RISK: 1%/trade, daily loss limit, spread guard, lot dari risiko |
//|  Prinsip pasca-ERIDA: conflict = satu posisi; cooldown = tidak.  |
//+------------------------------------------------------------------+
#property strict
#property version   "0.730"

#include <Trade\Trade.mqh>

//====================================================
// INPUTS
//====================================================

input group "=== ENTRY (TERKALIBRASI FASE 2) ==="
input int    ER_WindowSlow   = 48;     // Jendela ER trend [CAL]
input double TrendThreshold  = 30.0;   // ER-Slow minimum [CAL]
input int    SwingLookback   = 20;     // Jendela impuls pullback (standing rule)
input double PB_Min          = 20.0;   // Depth minimum % [CAL]
input double PB_Max          = 40.0;   // Depth maksimum % [CAL]

input group "=== STOP LOSS / TAKE PROFIT (DUNGU) ==="
input double PB_InvalidDepth = 65.0;   // Depth invalidasi utk SL [data: 60-80 mati]
input double SL_BufferATR    = 0.20;   // Buffer di bawah invalidasi (xATR) [UNCAL]
input double MinSL_ATR       = 0.50;   // SL minimal (xATR) - hindari lot raksasa
input double MaxSL_ATR       = 3.00;   // SL maksimal (xATR) - skip jika lebih [UNCAL]
input double RR              = 1.5;    // TP tetap = RR x jarak SL
input int    MaxHoldBars     = 80;     // Time stop (bar) - horizon kalibrasi

input group "=== RISK ==="
input double RiskPercent      = 1.0;   // Risiko per trade (% balance)
input double MaxLots          = 5.0;   // Pagar lot absolut (safety net)
input double DailyLossPercent = 3.0;   // Stop entry harian (% equity)
input int    MaxSpreadPoints  = 50;    // Spread maksimum saat entry [UNCAL]

input group "=== LAIN-LAIN ==="
input int    ATR_Period      = 14;
input long   MagicNumber     = 70200;
input bool   EnableLogging   = true;
input bool   UseCommonFolder = true;

//====================================================
// GLOBAL
//====================================================

CTrade   trade;

datetime LastBarTime   = 0;
string   LogFileName   = "";

long     g_lastPosId   = 0;      // posisi yang sedang/baru saja hidup
double   g_riskMoney   = 0;      // risiko uang posisi berjalan (utk R)

int      handleATR     = INVALID_HANDLE;

int      g_dayAnchor   = -1;     // hari utk daily loss
double   g_dayEquity   = 0;

// nilai sensor bar tertutup terakhir
double   ER_Slow = -1;
int      DirSlow = 0;
double   PB_Depth = -1;
int      PB_Bars  = -1;
double   ImpExtreme = 0, ImpBase = 0;   // impuls: ekstrem & dasar
double   ATRValue = 0;

//====================================================
// SENSOR 1 : TREND EFFICIENCY (identik 0.7.1)
//====================================================

double CalcEfficiency(const int window, const int shift, int &dir)
{
   dir = 0;

   if(window < 2)
      return -1;

   if(Bars(_Symbol,_Period) < window + shift + 2)
      return -1;

   double net =
      iClose(_Symbol,_Period,shift) -
      iClose(_Symbol,_Period,shift + window);

   double path = 0.0;

   for(int i = shift; i < shift + window; i++)
   {
      path += MathAbs(
         iClose(_Symbol,_Period,i) -
         iClose(_Symbol,_Period,i + 1));
   }

   if(path <= 0.0)
      return 0.0;

   if(net > 0.0)      dir = +1;
   else if(net < 0.0) dir = -1;

   return 100.0 * MathAbs(net) / path;
}

//====================================================
// SENSOR 3 : PULLBACK (identik 0.7.1 + ekspor impuls)
//====================================================

void DetectPullback()
{
   PB_Depth   = -1;
   PB_Bars    = -1;
   ImpExtreme = 0;
   ImpBase    = 0;

   if(DirSlow == 0)
      return;

   if(Bars(_Symbol,_Period) < SwingLookback * 2 + 5)
      return;

   if(DirSlow > 0)
   {
      int hiBar = iHighest(_Symbol,_Period,MODE_HIGH,SwingLookback,1);

      if(hiBar < 1)
         return;

      double extreme = iHigh(_Symbol,_Period,hiBar);

      int loBar = iLowest(_Symbol,_Period,MODE_LOW,SwingLookback,hiBar);

      if(loBar < hiBar)
         return;

      double base  = iLow(_Symbol,_Period,loBar);
      double range = extreme - base;

      if(range <= 0)
         return;

      int    retBar = iLowest(_Symbol,_Period,MODE_LOW,hiBar,1);
      double retLow = iLow(_Symbol,_Period,retBar);

      PB_Depth   = 100.0 * (extreme - retLow) / range;
      PB_Bars    = hiBar;
      ImpExtreme = extreme;
      ImpBase    = base;
   }
   else
   {
      int loBar = iLowest(_Symbol,_Period,MODE_LOW,SwingLookback,1);

      if(loBar < 1)
         return;

      double extreme = iLow(_Symbol,_Period,loBar);

      int hiBar = iHighest(_Symbol,_Period,MODE_HIGH,SwingLookback,loBar);

      if(hiBar < loBar)
         return;

      double base  = iHigh(_Symbol,_Period,hiBar);
      double range = base - extreme;

      if(range <= 0)
         return;

      int    retBar  = iHighest(_Symbol,_Period,MODE_HIGH,loBar,1);
      double retHigh = iHigh(_Symbol,_Period,retBar);

      PB_Depth   = 100.0 * (retHigh - extreme) / range;
      PB_Bars    = loBar;
      ImpExtreme = extreme;
      ImpBase    = base;
   }
}

//====================================================
// ATR
//====================================================

double GetATR()
{
   if(handleATR == INVALID_HANDLE)
      return 0.0;

   double buf[];

   if(CopyBuffer(handleATR, 0, 1, 1, buf) < 1)
      return 0.0;

   return buf[0];
}

//====================================================
// LOGGER (ENTRY / EXIT / info)
//====================================================

void LogRow(const string rowType,
            const string f1="", const string f2="",
            const string f3="", const string f4="",
            const string f5="", const string f6="",
            const string f7="", const string f8="",
            const string f9="", const string f10="")
{
   if(!EnableLogging)
      return;

   int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI;

   if(UseCommonFolder)
      flags |= FILE_COMMON;

   int fh = FileOpen(LogFileName, flags, ',');

   if(fh == INVALID_HANDLE)
      return;

   if(FileSize(fh) == 0)
   {
      FileWrite(fh,
         "type","time","posid",
         "dir","price","sl","tp","lots",
         "risk_money","er_slow","pb_depth","info");
      // ENTRY : dir,price,sl,tp,lots,risk,er,depth,spread
      // EXIT  : profit di kolom price, balance di kolom sl
   }

   FileSeek(fh, 0, SEEK_END);

   FileWrite(fh, rowType,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES|TIME_SECONDS),
      f1,f2,f3,f4,f5,f6,f7,f8,f9,f10);

   FileClose(fh);
}

//====================================================
// LOT DARI RISIKO
//====================================================
// Mengembalikan 0 kalau risiko 1% tidak bisa dihormati
// (lot hasil hitung < lot minimum) -> trade DILEWATI,
// bukan dipaksakan dengan risiko lebih besar.
//----------------------------------------------------

double CalcLots(const double entryPrice, const double slPrice,
                const int dir, double &riskMoney)
{
   riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;

   // FIX 0.7.3: JANGAN percaya aritmetika tick mentah.
   // Bug 0.7.2: tick_value/tick_size broker membuat risiko
   // riil 10x lipat dari niat. OrderCalcProfit menghitung
   // rugi per lot dengan spesifikasi kontrak yang benar.
   double lossPerLot = 0;

   ENUM_ORDER_TYPE ot = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   if(OrderCalcProfit(ot, _Symbol, 1.0,
                      entryPrice, slPrice, lossPerLot))
   {
      lossPerLot = MathAbs(lossPerLot);
   }
   else
   {
      // fallback: contract size eksplisit
      double contract =
         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

      if(contract <= 0)
         return 0;

      lossPerLot = MathAbs(entryPrice - slPrice) * contract;
   }

   if(lossPerLot <= 0)
      return 0;

   double lots = riskMoney / lossPerLot;

   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step > 0)
      lots = MathFloor(lots / step) * step;

   if(lots < minV)
      return 0;              // hormati batas risiko: skip

   if(lots > maxV)
      lots = maxV;

   if(lots > MaxLots)
      lots = MaxLots;        // safety net absolut (risiko < target = aman)

   riskMoney = lots * lossPerLot;   // risiko riil setelah pembulatan

   return lots;
}

//====================================================
// DAILY LOSS GUARD
//====================================================

bool DailyLossHit()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(dt.day != g_dayAnchor)
   {
      g_dayAnchor = dt.day;
      g_dayEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   if(g_dayEquity <= 0)
      return false;

   double ddPct = 100.0 *
      (AccountInfoDouble(ACCOUNT_EQUITY) - g_dayEquity) / g_dayEquity;

   return (ddPct <= -DailyLossPercent);
}

//====================================================
// POSISI
//====================================================

bool HasPosition()
{
   if(!PositionSelect(_Symbol))
      return false;

   return ((long)PositionGetInteger(POSITION_MAGIC) == MagicNumber);
}

void CheckClosedPosition()
{
   if(g_lastPosId <= 0 || HasPosition())
      return;

   // posisi kita sudah tertutup -> ambil hasilnya dari history
   if(HistorySelectByPosition(g_lastPosId))
   {
      double profit = 0;
      datetime closeTime = 0;

      int total = HistoryDealsTotal();

      for(int i = 0; i < total; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);

         if(dealTicket == 0)
            continue;

         profit +=
            HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
            HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
            HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

         if((long)HistoryDealGetInteger(dealTicket, DEAL_ENTRY)
            == DEAL_ENTRY_OUT)
            closeTime =
               (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      }

      LogRow("EXIT",
         IntegerToString((int)g_lastPosId),
         "",                                   // dir kosong
         DoubleToString(profit,2),             // kolom price = profit
         DoubleToString(
            AccountInfoDouble(ACCOUNT_BALANCE),2), // kolom sl = balance
         "","",
         DoubleToString(g_riskMoney,2),
         "","","");
   }

   g_lastPosId = 0;
   g_riskMoney = 0;
}

void TimeStopCheck()
{
   if(!HasPosition())
      return;

   datetime openTime =
      (datetime)PositionGetInteger(POSITION_TIME);

   int barsHeld =
      (int)((TimeCurrent() - openTime) / PeriodSeconds(_Period));

   if(barsHeld >= MaxHoldBars)
   {
      trade.PositionClose(_Symbol);
      Print("AIDEN073: time stop setelah ", barsHeld, " bar");
   }
}

//====================================================
// ENTRY LOGIC
//====================================================

void TryEnter()
{
   if(HasPosition())
      return;

   if(DailyLossHit())
      return;

   // ---- kondisi terkalibrasi
   if(ER_Slow < TrendThreshold || DirSlow == 0)
      return;

   if(PB_Depth < PB_Min || PB_Depth > PB_Max)
      return;

   // ---- spread guard
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(spread > MaxSpreadPoints)
      return;

   if(ATRValue <= 0)
      return;

   double range = MathAbs(ImpExtreme - ImpBase);

   if(range <= 0)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double entry, sl, slDist;

   if(DirSlow > 0)
   {
      entry = ask;

      // SL = level depth invalidasi + buffer
      double invalid =
         ImpExtreme - range * PB_InvalidDepth / 100.0;

      sl = invalid - SL_BufferATR * ATRValue;

      slDist = entry - sl;
   }
   else
   {
      entry = bid;

      double invalid =
         ImpExtreme + range * PB_InvalidDepth / 100.0;

      sl = invalid + SL_BufferATR * ATRValue;

      slDist = sl - entry;
   }

   if(slDist <= 0)
      return;

   // ---- pagar jarak SL (dalam ATR)
   if(slDist < MinSL_ATR * ATRValue)
   {
      slDist = MinSL_ATR * ATRValue;
      sl = (DirSlow > 0) ? entry - slDist : entry + slDist;
   }

   if(slDist > MaxSL_ATR * ATRValue)
      return;   // struktur terlalu lebar utk risiko wajar: skip

   // ---- stops level broker
   double stopsLevel =
      SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   if(slDist < stopsLevel)
      return;

   double tpDist = RR * slDist;

   if(tpDist < stopsLevel)
      return;

   double tp = (DirSlow > 0) ? entry + tpDist : entry - tpDist;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   // ---- lot dari risiko
   double riskMoney = 0;
   double lots = CalcLots(entry, sl, DirSlow, riskMoney);

   if(lots <= 0)
      return;

   // ---- eksekusi
   bool ok = (DirSlow > 0)
      ? trade.Buy (lots, _Symbol, 0.0, sl, tp)
      : trade.Sell(lots, _Symbol, 0.0, sl, tp);

   if(!ok)
   {
      Print("AIDEN073: order gagal, retcode=",
            trade.ResultRetcode(), " (",
            trade.ResultRetcodeDescription(), ")");
      return;
   }

   if(PositionSelect(_Symbol))
   {
      g_lastPosId =
         (long)PositionGetInteger(POSITION_IDENTIFIER);
      g_riskMoney = riskMoney;

      LogRow("ENTRY",
         IntegerToString((int)g_lastPosId),
         IntegerToString(DirSlow),
         DoubleToString(
            PositionGetDouble(POSITION_PRICE_OPEN),_Digits),
         DoubleToString(sl,_Digits),
         DoubleToString(tp,_Digits),
         DoubleToString(lots,2),
         DoubleToString(riskMoney,2),
         DoubleToString(ER_Slow,2),
         DoubleToString(PB_Depth,2),
         "spread=" + IntegerToString((int)spread));
   }
}

//====================================================
// PROSES PER BAR TERTUTUP
//====================================================

void ProcessNewBar()
{
   CheckClosedPosition();     // log hasil posisi yang baru tutup

   ER_Slow  = CalcEfficiency(ER_WindowSlow, 1, DirSlow);
   ATRValue = GetATR();

   DetectPullback();

   TimeStopCheck();

   TryEnter();
}

//====================================================
// INIT / DEINIT / MAIN
//====================================================

int OnInit()
{
   handleATR = iATR(_Symbol, _Period, ATR_Period);

   if(handleATR == INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFillingBySymbol(_Symbol);

   LogFileName =
      "AIDEN073_trades_" + _Symbol + "_" +
      EnumToString(_Period) + ".csv";

   LastBarTime = 0;
   g_lastPosId = 0;
   g_dayAnchor = -1;

   Print("AIDEN 0.7.3 EA init. Trade log: ", LogFileName);

   // Transparansi spesifikasi broker (audit lot sizing 0.7.3)
   double _tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double _ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double _cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   double _testLoss = 0;
   double _refPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(_refPrice > 1.0 &&
      OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0,
                      _refPrice, _refPrice - 1.0, _testLoss))
   {
      Print("AIDEN073 spec: contract=", _cs,
            " tickValue=", _tv, " tickSize=", _ts,
            " | rugi per $1 move per 1 lot = ",
            DoubleToString(MathAbs(_testLoss), 2), " USD",
            " (tick-math lama akan bilang: ",
            DoubleToString(_ts > 0 ? 1.0/_ts*_tv : 0, 2), " USD)");
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(handleATR != INVALID_HANDLE)
      IndicatorRelease(handleATR);
}

void OnTick()
{
   datetime currentBar = iTime(_Symbol,_Period,0);

   if(currentBar != LastBarTime)
   {
      LastBarTime = currentBar;
      ProcessNewBar();
   }
}
//+------------------------------------------------------------------+
