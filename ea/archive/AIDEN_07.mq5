//+------------------------------------------------------------------+
//|                                                    AIDEN_07.mq5  |
//|                     AIDEN 0.7 - Sensor Core + Data Recorder      |
//|                                                                  |
//|  FASE 1 : Sensor 1 (TrendEfficiency) + CSV Logger                |
//|                                                                  |
//|  Filosofi 0.7:                                                   |
//|   1. Satu sensor = satu pertanyaan yang tidak bisa dijawab       |
//|      sensor lain.                                                |
//|   2. Tidak ada threshold masuk kode tanpa rencana kalibrasi.     |
//|      Semua angka di input diberi tanda [UNCAL] = belum           |
//|      dikalibrasi, nilainya sementara.                            |
//|   3. Logging bukan fitur tambahan - ia lahir bersama sensor.     |
//|   4. Urutan pembuktian: sensor -> entry -> manajemen.            |
//|                                                                  |
//|  Sensor 1 - TrendEfficiency (Efficiency Ratio):                  |
//|      ER = 100 * |perpindahan netto| / total pergerakan           |
//|      Skala 0-100 sejati: 0 = pasar tidak ke mana-mana,           |
//|      100 = setiap langkah searah. Tiga jendela (fast/mid/slow)   |
//|      direkam sekaligus agar Fase 2 bisa memilih jendela          |
//|      terbaik dari data, bukan dari selera.                       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0
#property version   "0.700"

//====================================================
// INPUTS
//====================================================

input group "=== SENSOR 1 : TREND EFFICIENCY ==="
input int    ER_WindowFast    = 12;    // Jendela cepat  (bar) [UNCAL]
input int    ER_WindowMid     = 24;    // Jendela menengah (bar) [UNCAL]
input int    ER_WindowSlow    = 48;    // Jendela lambat (bar) [UNCAL]
input double NeutralThreshold = 20.0;  // Ambang Neutral (standing rule) [UNCAL]

input group "=== LOGGER ==="
input bool   EnableLogging    = true;  // Rekam setiap bar tertutup ke CSV
input bool   UseCommonFolder  = true;  // Simpan di Common\Files (terbaca juga oleh Strategy Tester)

input group "=== LAIN-LAIN ==="
input int    ATR_Period       = 14;    // Periode ATR (untuk normalisasi di Fase 2)

//====================================================
// GLOBAL
//====================================================

datetime LastBarTime = 0;

int      handleATR   = INVALID_HANDLE;

string   LogFileName = "";
long     RowsLogged  = 0;

// Nilai sensor bar tertutup terakhir (shift 1)
double   ER_Fast = -1, ER_Mid = -1, ER_Slow = -1;
int      DirFast = 0,  DirMid = 0,  DirSlow = 0;
double   ATRValue = 0;
string   Bias = "NO_DATA";

//====================================================
// SENSOR 1 : TREND EFFICIENCY
//====================================================
// ER dihitung pada bar TERTUTUP (shift 1) agar tidak
// pernah membaca candle yang masih berjalan.
// Return: 0..100, atau -1 jika data belum cukup.
// dir: +1 netto naik, -1 netto turun, 0 datar sempurna.
//----------------------------------------------------

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

//----------------------------------------------------
// Bias sederhana dari satu variasi ER.
// Catatan: NeutralThreshold berstatus [UNCAL] -
// nilai finalnya akan ditarik dari persentil data
// di Fase 2, bukan dari angka 20 ini.
//----------------------------------------------------

string BiasFrom(const double er, const int dir)
{
   if(er < 0)
      return "NO_DATA";

   if(er < NeutralThreshold || dir == 0)
      return "NEUTRAL";

   return (dir > 0) ? "BULLISH" : "BEARISH";
}

//====================================================
// ATR (handle global, dibuat sekali di OnInit -
// tidak ada lagi churn buat/lepas handle per bar)
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
// Satu baris per bar tertutup. File dibuka-tulis-tutup
// setiap bar agar aman terhadap crash/restart.
// Duplikat antar-restart mungkin terjadi; skrip Python
// melakukan dedup berdasarkan kolom time.
//----------------------------------------------------

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
      Print("AIDEN07: gagal membuka log '",
            LogFileName, "' err=", GetLastError());
      return;
   }

   // Header hanya saat file baru
   if(FileSize(fh) == 0)
   {
      FileWrite(fh,
         "time","open","high","low","close","tick_volume",
         "spread_points","atr",
         "er_fast","dir_fast",
         "er_mid","dir_mid",
         "er_slow","dir_slow",
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
      Bias);

   FileClose(fh);

   RowsLogged++;
}

//====================================================
// DASHBOARD (minimal - untuk mata manusia saja;
// mesin membaca CSV, bukan label)
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

void UpdateDashboard()
{
   color biasClr = clrGray;

   if(Bias == "BULLISH") biasClr = clrLime;
   if(Bias == "BEARISH") biasClr = clrOrangeRed;

   SetLabel("A07_00","AIDEN 0.7 | SENSOR CORE",           20, clrGold);
   SetLabel("A07_01","Fase      : 1 (PEREKAMAN)",          40);
   SetLabel("A07_02","--------------------------",         60, clrDimGray);

   SetLabel("A07_03","ER Fast " +
      IntegerToString(ER_WindowFast) + "  : " +
      DoubleToString(ER_Fast,1) + " " + DirText(DirFast),  80);

   SetLabel("A07_04","ER Mid  " +
      IntegerToString(ER_WindowMid) + "  : " +
      DoubleToString(ER_Mid,1) + " " + DirText(DirMid),   100);

   SetLabel("A07_05","ER Slow " +
      IntegerToString(ER_WindowSlow) + "  : " +
      DoubleToString(ER_Slow,1) + " " + DirText(DirSlow), 120);

   SetLabel("A07_06","Bias(mid) : " + Bias,               140, biasClr);

   SetLabel("A07_07","ATR       : " +
      DoubleToString(ATRValue,_Digits),                   160);

   SetLabel("A07_08","Log       : " +
      (EnableLogging ? "ON" : "OFF") + " (" +
      IntegerToString((int)RowsLogged) + " baris)",       180,
      EnableLogging ? clrWhite : clrOrangeRed);

   SetLabel("A07_09","Bar       : " +
      TimeToString(iTime(_Symbol,_Period,1),
                   TIME_DATE|TIME_MINUTES),               200, clrSilver);
}

//====================================================
// PROSES PER BAR TERTUTUP
//====================================================

void ProcessNewBar()
{
   ER_Fast = CalcEfficiency(ER_WindowFast, 1, DirFast);
   ER_Mid  = CalcEfficiency(ER_WindowMid,  1, DirMid);
   ER_Slow = CalcEfficiency(ER_WindowSlow, 1, DirSlow);

   ATRValue = GetATR();

   // Bias tampilan memakai jendela menengah.
   // Ini pilihan tampilan, bukan keputusan trading -
   // Fase 2 yang menentukan jendela mana yang berbicara.
   Bias = BiasFrom(ER_Mid, DirMid);

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
      "AIDEN07_" + _Symbol + "_" +
      EnumToString(_Period) + ".csv";

   LastBarTime = 0;
   RowsLogged  = 0;

   Print("AIDEN 0.7 init. Log file: ", LogFileName,
         UseCommonFolder ? " (Common\\Files)" : " (MQL5\\Files)");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(handleATR != INVALID_HANDLE)
      IndicatorRelease(handleATR);

   for(int i = 0; i <= 9; i++)
      ObjectDelete(0, "A07_0" + IntegerToString(i));
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
