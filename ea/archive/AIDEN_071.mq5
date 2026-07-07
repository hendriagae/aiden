//+------------------------------------------------------------------+
//|                                                   AIDEN_071.mq5  |
//|                     AIDEN 0.7.1 - Sensor Core + Data Recorder    |
//|                                                                  |
//|  FASE 1-2 lanjutan:                                              |
//|    Sensor 1 : TrendEfficiency  [TERKALIBRASI sebagian]           |
//|               - ER-Slow >= 30  : trend skala harian (bukti:      |
//|                 edge 1.23-1.62 @ horizon 40-80 bar, 2024-2026)   |
//|               - ER-Mid  >= 50  : ledakan rawan koreksi           |
//|    Sensor 2 : SwingStructure   [BARU - diadili di Fase 2]        |
//|    Sensor 3 : Pullback         [BARU - diadili di Fase 2]        |
//|                                                                  |
//|  Hipotesis yang diuji versi ini:                                 |
//|    "trend harian + struktur searah + pullback selesai"           |
//|    harus terbukti LEBIH BAIK daripada "trend harian saja".       |
//|    Sensor yang tidak menambah apa-apa akan dipangkas.            |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0
#property version   "0.710"

//====================================================
// INPUTS
//====================================================

input group "=== SENSOR 1 : TREND EFFICIENCY ==="
input int    ER_WindowFast    = 12;    // Jendela cepat (bar) [UNCAL]
input int    ER_WindowMid     = 24;    // Jendela menengah (bar) - fade zone >=50 [CAL]
input int    ER_WindowSlow    = 48;    // Jendela lambat (bar) - trend >=30 [CAL]
input double NeutralThreshold = 20.0;  // Ambang Neutral tampilan [UNCAL]

input group "=== SENSOR 2 : SWING STRUCTURE ==="
input int    PivotStrength    = 3;     // K bar kiri-kanan pivot [UNCAL]
input int    SwingScanBars    = 200;   // Kedalaman scan pivot (bar)

input group "=== SENSOR 3 : PULLBACK ==="
input int    SwingLookback    = 20;    // Jendela impuls (standing rule) [UNCAL]

input group "=== LOGGER ==="
input bool   EnableLogging    = true;  // Rekam setiap bar tertutup ke CSV
input bool   UseCommonFolder  = true;  // Simpan di Common\Files

input group "=== LAIN-LAIN ==="
input int    ATR_Period       = 14;    // Periode ATR

//====================================================
// GLOBAL
//====================================================

datetime LastBarTime = 0;
int      handleATR   = INVALID_HANDLE;
string   LogFileName = "";
long     RowsLogged  = 0;

// --- Sensor 1
double   ER_Fast = -1, ER_Mid = -1, ER_Slow = -1;
int      DirFast = 0,  DirMid = 0,  DirSlow = 0;
string   Bias = "NO_DATA";

// --- Sensor 2
int      StructState = 0;      // +1 HH+HL, -1 LH+LL, 0 campur/tak cukup
double   SwingHigh = 0, SwingLow = 0;   // pivot terkonfirmasi terakhir
int      SwingHighAge = -1, SwingLowAge = -1;

// --- Sensor 3
double   PB_Depth = -1;        // % retrace impuls; -1 = tak berlaku
int      PB_Recov = 0;         // 1 = candle pemulihan searah trend
int      PB_Bars  = -1;        // bar sejak ekstrem impuls

double   ATRValue = 0;

//====================================================
// SENSOR 1 : TREND EFFICIENCY
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

string BiasFrom(const double er, const int dir)
{
   if(er < 0)                              return "NO_DATA";
   if(er < NeutralThreshold || dir == 0)   return "NEUTRAL";
   return (dir > 0) ? "BULLISH" : "BEARISH";
}

//====================================================
// SENSOR 2 : SWING STRUCTURE
//====================================================
// Pivot terkonfirmasi: high/low bar i lebih ekstrem dari
// PivotStrength bar di KEDUA sisinya. Karena butuh K bar
// di kanan, pivot baru sah setelah K bar lewat -> tidak
// pernah repaint. Struktur ditentukan dari perbandingan
// dua pivot high terakhir dan dua pivot low terakhir:
//   HH + HL -> +1 (bullish)
//   LH + LL -> -1 (bearish)
//   campur  ->  0
//----------------------------------------------------

void DetectStructure()
{
   StructState  = 0;
   SwingHigh    = 0;   SwingLow    = 0;
   SwingHighAge = -1;  SwingLowAge = -1;

   int need = SwingScanBars + PivotStrength + 2;

   if(Bars(_Symbol,_Period) < need)
      return;

   double sh[2], sl[2];
   int    foundH = 0, foundL = 0;

   for(int i = PivotStrength + 1;
       i <= SwingScanBars && (foundH < 2 || foundL < 2);
       i++)
   {
      double h0 = iHigh(_Symbol,_Period,i);
      double l0 = iLow (_Symbol,_Period,i);

      bool isH = true, isL = true;

      for(int j = i - PivotStrength; j <= i + PivotStrength; j++)
      {
         if(j == i)
            continue;

         if(iHigh(_Symbol,_Period,j) >= h0) isH = false;
         if(iLow (_Symbol,_Period,j) <= l0) isL = false;

         if(!isH && !isL)
            break;
      }

      if(isH && foundH < 2)
      {
         sh[foundH] = h0;

         if(foundH == 0)
         {
            SwingHigh    = h0;
            SwingHighAge = i;
         }

         foundH++;
      }

      if(isL && foundL < 2)
      {
         sl[foundL] = l0;

         if(foundL == 0)
         {
            SwingLow    = l0;
            SwingLowAge = i;
         }

         foundL++;
      }
   }

   if(foundH < 2 || foundL < 2)
      return;

   bool hh = (sh[0] > sh[1]);
   bool hl = (sl[0] > sl[1]);
   bool lh = (sh[0] < sh[1]);
   bool ll = (sl[0] < sl[1]);

   if(hh && hl)      StructState = +1;
   else if(lh && ll) StructState = -1;
   else              StructState = 0;
}

//====================================================
// SENSOR 3 : PULLBACK (depth + recovery)
//====================================================
// Konteks arah = DirSlow (definisi trend terkalibrasi).
// Bull: impuls = dari low dasar menuju high tertinggi
//       dalam SwingLookback bar; depth = % retrace dari
//       high itu ke low terendah SETELAHNYA.
// Recovery (bull): bar tertutup terakhir close menembus
//       high bar sebelumnya -> candle pemulihan. [UNCAL]
// Depth > 100 dimungkinkan = impuls tertelan (failure).
//----------------------------------------------------

void DetectPullback()
{
   PB_Depth = -1;
   PB_Recov = 0;
   PB_Bars  = -1;

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

      // dasar impuls: low terendah di belakang ekstrem
      int loBar = iLowest(_Symbol,_Period,MODE_LOW,SwingLookback,hiBar);

      if(loBar < hiBar)
         return;

      double base  = iLow(_Symbol,_Period,loBar);
      double range = extreme - base;

      if(range <= 0)
         return;

      // retrace terendah setelah ekstrem (shift 1..hiBar)
      int    retBar = iLowest(_Symbol,_Period,MODE_LOW,hiBar,1);
      double retLow = iLow(_Symbol,_Period,retBar);

      PB_Depth = 100.0 * (extreme - retLow) / range;
      PB_Bars  = hiBar;

      if(iClose(_Symbol,_Period,1) > iHigh(_Symbol,_Period,2))
         PB_Recov = 1;
   }
   else // DirSlow < 0
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

      PB_Depth = 100.0 * (retHigh - extreme) / range;
      PB_Bars  = loBar;

      if(iClose(_Symbol,_Period,1) < iLow(_Symbol,_Period,2))
         PB_Recov = 1;
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
// LOGGER
//====================================================

void LogBar()
{
   if(!EnableLogging)
      return;

   int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI;

   if(UseCommonFolder)
      flags |= FILE_COMMON;

   int fh = FileOpen(LogFileName, flags, ',');

   if(fh == INVALID_HANDLE)
   {
      Print("AIDEN071: gagal membuka log '",
            LogFileName, "' err=", GetLastError());
      return;
   }

   if(FileSize(fh) == 0)
   {
      FileWrite(fh,
         "time","open","high","low","close","tick_volume",
         "spread_points","atr",
         "er_fast","dir_fast",
         "er_mid","dir_mid",
         "er_slow","dir_slow",
         "struct_state","sw_high","sw_low",
         "pb_depth","pb_recov","pb_bars",
         "bias");
   }

   FileSeek(fh, 0, SEEK_END);

   FileWrite(fh,
      TimeToString(iTime(_Symbol,_Period,1),
                   TIME_DATE|TIME_MINUTES|TIME_SECONDS),
      DoubleToString(iOpen (_Symbol,_Period,1),_Digits),
      DoubleToString(iHigh (_Symbol,_Period,1),_Digits),
      DoubleToString(iLow  (_Symbol,_Period,1),_Digits),
      DoubleToString(iClose(_Symbol,_Period,1),_Digits),
      IntegerToString(iVolume(_Symbol,_Period,1)),
      IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)),
      DoubleToString(ATRValue,_Digits),
      DoubleToString(ER_Fast,2),  IntegerToString(DirFast),
      DoubleToString(ER_Mid,2),   IntegerToString(DirMid),
      DoubleToString(ER_Slow,2),  IntegerToString(DirSlow),
      IntegerToString(StructState),
      DoubleToString(SwingHigh,_Digits),
      DoubleToString(SwingLow,_Digits),
      DoubleToString(PB_Depth,2),
      IntegerToString(PB_Recov),
      IntegerToString(PB_Bars),
      Bias);

   FileClose(fh);

   RowsLogged++;
}

//====================================================
// DASHBOARD
//====================================================

void SetLabel(const string name, const string text,
              const int y, const color clr = clrWhite)
{
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);

   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,330);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetString (0,name,OBJPROP_FONT,"Consolas");
   ObjectSetString (0,name,OBJPROP_TEXT,text);
}

string DirText(const int dir)
{
   if(dir > 0) return "UP";
   if(dir < 0) return "DOWN";
   return "FLAT";
}

string StructText(const int s)
{
   if(s > 0) return "BULL (HH+HL)";
   if(s < 0) return "BEAR (LH+LL)";
   return "MIXED";
}

void UpdateDashboard()
{
   color biasClr = clrGray;

   if(Bias == "BULLISH") biasClr = clrLime;
   if(Bias == "BEARISH") biasClr = clrOrangeRed;

   color structClr = clrGray;

   if(StructState > 0) structClr = clrLime;
   if(StructState < 0) structClr = clrOrangeRed;

   // Rezim terkalibrasi dari Fase 2
   string rezim = "NO_TREND";
   color  rezimClr = clrGray;

   if(ER_Slow >= 30 && DirSlow != 0)
   {
      rezim    = (DirSlow > 0) ? "TREND_UP" : "TREND_DOWN";
      rezimClr = (DirSlow > 0) ? clrLime : clrOrangeRed;
   }

   string fade = (ER_Mid >= 50 && DirMid != 0) ? "YA" : "tidak";

   SetLabel("A71_00","AIDEN 0.7.1 | SENSOR CORE",          20, clrGold);
   SetLabel("A71_01","Fase      : 2 (KALIBRASI S2+S3)",     40);
   SetLabel("A71_02","--------------------------",          60, clrDimGray);

   SetLabel("A71_03","ER F/M/S  : " +
      DoubleToString(ER_Fast,0) + " / " +
      DoubleToString(ER_Mid,0)  + " / " +
      DoubleToString(ER_Slow,0),                            80);

   SetLabel("A71_04","Rezim     : " + rezim +
      " (ERs>=30)",                                        100, rezimClr);

   SetLabel("A71_05","FadeZone  : " + fade +
      " (ERm>=50)",                                        120);

   SetLabel("A71_06","Struktur  : " + StructText(StructState), 140, structClr);

   SetLabel("A71_07","SwingH/L  : " +
      DoubleToString(SwingHigh,_Digits) + " / " +
      DoubleToString(SwingLow,_Digits),                    160, clrSilver);

   SetLabel("A71_08","PB Depth  : " +
      (PB_Depth < 0 ? "n/a" : DoubleToString(PB_Depth,0) + "%") +
      "  Recov: " + (PB_Recov == 1 ? "YA" : "-"),          180);

   SetLabel("A71_09","Bias(mid) : " + Bias,                200, biasClr);

   SetLabel("A71_10","ATR       : " +
      DoubleToString(ATRValue,_Digits),                    220);

   SetLabel("A71_11","Log       : " +
      (EnableLogging ? "ON" : "OFF") + " (" +
      IntegerToString((int)RowsLogged) + " baris)",        240,
      EnableLogging ? clrWhite : clrOrangeRed);

   SetLabel("A71_12","Bar       : " +
      TimeToString(iTime(_Symbol,_Period,1),
                   TIME_DATE|TIME_MINUTES),                260, clrSilver);
}

//====================================================
// PROSES PER BAR TERTUTUP
//====================================================

void ProcessNewBar()
{
   ER_Fast = CalcEfficiency(ER_WindowFast, 1, DirFast);
   ER_Mid  = CalcEfficiency(ER_WindowMid,  1, DirMid);
   ER_Slow = CalcEfficiency(ER_WindowSlow, 1, DirSlow);

   Bias = BiasFrom(ER_Mid, DirMid);

   DetectStructure();

   DetectPullback();   // memakai DirSlow -> harus setelah Sensor 1

   ATRValue = GetATR();

   LogBar();

   UpdateDashboard();
}

//====================================================
// INIT / DEINIT / MAIN
//====================================================

int OnInit()
{
   handleATR = iATR(_Symbol, _Period, ATR_Period);

   if(handleATR == INVALID_HANDLE)
      return INIT_FAILED;

   LogFileName =
      "AIDEN071_" + _Symbol + "_" +
      EnumToString(_Period) + ".csv";

   LastBarTime = 0;
   RowsLogged  = 0;

   Print("AIDEN 0.7.1 init. Log file: ", LogFileName,
         UseCommonFolder ? " (Common\\Files)" : " (MQL5\\Files)");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(handleATR != INVALID_HANDLE)
      IndicatorRelease(handleATR);

   for(int i = 0; i <= 12; i++)
   {
      string suffix = (i < 10 ? "0" : "") + IntegerToString(i);
      ObjectDelete(0, "A71_" + suffix);
   }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   datetime currentBar = iTime(_Symbol,_Period,0);

   if(currentBar != LastBarTime)
   {
      LastBarTime = currentBar;
      ProcessNewBar();
   }

   return rates_total;
}
//+------------------------------------------------------------------+
