//+------------------------------------------------------------------+
//|                                                    BBSqueeze.mq5 |
//|  Bollinger Squeeze: squeeze -> PRE -> BREAKOUT                   |
//|                                                                  |
//|  Pannello: BandWidth                                             |
//|    blu     = normale                                             |
//|    rosso   = squeeze valido                                      |
//|    arancio = squeeze corto o PRONTO (squeeze appena finito)      |
//|  Linee: Lowest Contraction / Highest Expansion (lookback)        |
//|  Sul prezzo: freccia sottile = PRE, freccia grossa = BREAKOUT,   |
//|  rettangolo = range dello squeeze.                               |
//|  Logica in BBSqueeze\SqueezeCommon.mqh (condivisa con dashboard  |
//|  ed EA).                                                          |
//+------------------------------------------------------------------+
#property copyright   "Dario"
#property version     "2.00"
#property description "Bollinger Squeeze - squeeze, PRE, BREAKOUT"

#property indicator_separate_window
#property indicator_buffers 13
#property indicator_plots   3

#property indicator_label1  "BandWidth"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue,clrRed,clrOrange
#property indicator_width1  2

#property indicator_label2  "Lowest Contraction"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrTeal
#property indicator_width2  1

#property indicator_label3  "Highest Expansion"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrLightPink
#property indicator_width3  1

#include <BBSqueeze\SqueezeCommon.mqh>

//--- input
input group "Bollinger / Squeeze"
input int           InpBBPeriod   = 20;            // Periodo Bollinger
input double        InpBBDev      = 2.0;           // Deviazioni standard
input ENUM_SQZ_MODE InpMode       = SQZ_BANDWIDTH; // Definizione base squeeze
input int           InpBWLookback = 125;           // Lookback minimo/massimo BW (barre)
input double        InpBWTolPct   = 10.0;          // Tolleranza % sopra il minimo
input int           InpKCPeriod   = 20;            // Keltner: periodo EMA + ATR
input double        InpKCMult     = 1.5;           // Keltner: moltiplicatore ATR
input bool          InpUseFlat    = true;          // Richiedi BW piatto
input int           InpFlatBars   = 10;            // Barre per piattezza
input double        InpFlatMax    = 0.15;          // Escursione max BW (frazione della media)
input bool          InpUseSlope   = true;          // Richiedi bande piatte
input int           InpATRPeriod  = 14;            // ATR per la pendenza
input double        InpSlopeMax   = 1.0;           // Pendenza max media centrale (x ATR)
input int           InpMinBars    = 5;             // Durata minima squeeze (barre)

input group "Segnali"
input int           InpArmBars    = 10;            // Barre valide dopo la fine dello squeeze
input double        InpTouchTol   = 0.10;          // Tolleranza tocco banda (frazione ampiezza)
input int           InpRiseBars   = 2;             // Barre di BW in salita
input int           InpConfBars   = 5;             // Barre utili per la conferma

input group "Grafica e avvisi"
input bool          InpArrows     = true;          // Frecce PRE / BREAKOUT sul prezzo
input bool          InpDrawRange  = true;          // Rettangolo del range di squeeze
input bool          InpAlerts     = false;         // Alert popup
input bool          InpPush       = false;         // Notifiche push (app MT5)

//--- buffer
double BW[], Clr[], LowC[], HighE[];
double State[];   // 0 niente, 1 squeeze corto/PRONTO, 2 squeeze valido   (iCustom buffer 4)
double PreEv[];   // +2/-2 sulla barra del PRE                           (iCustom buffer 5)
double BrkEv[];   // +3/-3 sulla barra del BREAKOUT                      (iCustom buffer 6)
double Up[], Mid[], Lo[], Ema[], AtrKC[], Atr[];

int hBB = INVALID_HANDLE, hEMA = INVALID_HANDLE, hATRkc = INVALID_HANDLE, hATR = INVALID_HANDLE;

SqzParams  P;
SqzTracker TR;
int        g_last = -1;     // ultima barra chiusa elaborata
bool       g_live = false;  // true dopo il primo calcolo completo
string     g_prefix;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBBPeriod < 2 || InpKCPeriod < 2 || InpATRPeriod < 1 || InpBWLookback < 2 || InpFlatBars < 2 ||
      InpRiseBars < 1 || InpConfBars < 1 || InpMinBars < 1 || InpArmBars < 0 || InpBBDev <= 0.0)
     {
      Print("BBSqueeze: parametri non validi");
      return INIT_PARAMETERS_INCORRECT;
     }

   P.bbPeriod = InpBBPeriod;   P.bbDev = InpBBDev;       P.mode = InpMode;
   P.bwLookback = InpBWLookback; P.bwTolPct = InpBWTolPct;
   P.kcPeriod = InpKCPeriod;   P.kcMult = InpKCMult;
   P.useFlat = InpUseFlat;     P.flatBars = InpFlatBars; P.flatMax = InpFlatMax;
   P.useSlope = InpUseSlope;   P.atrPeriod = InpATRPeriod; P.slopeMax = InpSlopeMax;
   P.minBars = InpMinBars;     P.armBars = InpArmBars;
   P.touchTol = InpTouchTol;   P.riseBars = InpRiseBars; P.confBars = InpConfBars;

   SetIndexBuffer(0,  BW,    INDICATOR_DATA);
   SetIndexBuffer(1,  Clr,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,  LowC,  INDICATOR_DATA);
   SetIndexBuffer(3,  HighE, INDICATOR_DATA);
   SetIndexBuffer(4,  State, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,  PreEv, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,  BrkEv, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,  Up,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,  Mid,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,  Lo,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, Ema,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, AtrKC, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, Atr,   INDICATOR_CALCULATIONS);

   for(int k = 0; k < 3; k++)
      PlotIndexSetDouble(k, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   hBB    = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDev, PRICE_CLOSE);
   hEMA   = iMA(_Symbol, _Period, InpKCPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hATRkc = iATR(_Symbol, _Period, InpKCPeriod);
   hATR   = iATR(_Symbol, _Period, InpATRPeriod);
   if(hBB == INVALID_HANDLE || hEMA == INVALID_HANDLE || hATRkc == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("BBSqueeze: errore creazione handle ", GetLastError());
      return INIT_FAILED;
     }

   g_prefix = "BBSqzI_" + IntegerToString(ChartWindowFind()) + "_";
   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("BBSqueeze(%d,%.1f)", InpBBPeriod, InpBBDev));
   IndicatorSetInteger(INDICATOR_DIGITS, 4);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hBB    != INVALID_HANDLE) IndicatorRelease(hBB);
   if(hEMA   != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hATRkc != INVALID_HANDLE) IndicatorRelease(hATRkc);
   if(hATR   != INVALID_HANDLE) IndicatorRelease(hATR);
   ObjectsDeleteAll(0, g_prefix);
  }

//+------------------------------------------------------------------+
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
   int firstValid = MathMax(MathMax(InpBBPeriod, InpKCPeriod), InpATRPeriod);
   int firstEval  = firstValid + SqzBarsNeeded(P);
   if(rates_total < firstEval + 2)
      return 0;

   if(BarsCalculated(hBB) < rates_total || BarsCalculated(hEMA) < rates_total ||
      BarsCalculated(hATRkc) < rates_total || BarsCalculated(hATR) < rates_total)
      return 0;

   bool full = (prev_calculated <= 0 || prev_calculated > rates_total);
   int toCopy = full ? rates_total : rates_total - prev_calculated + 1;

   if(CopyBuffer(hBB,    0, 0, toCopy, Mid)   <= 0) return 0;   // BASE_LINE
   if(CopyBuffer(hBB,    1, 0, toCopy, Up)    <= 0) return 0;   // UPPER_BAND
   if(CopyBuffer(hBB,    2, 0, toCopy, Lo)    <= 0) return 0;   // LOWER_BAND
   if(CopyBuffer(hEMA,   0, 0, toCopy, Ema)   <= 0) return 0;
   if(CopyBuffer(hATRkc, 0, 0, toCopy, AtrKC) <= 0) return 0;
   if(CopyBuffer(hATR,   0, 0, toCopy, Atr)   <= 0) return 0;

   if(full)
     {
      TR.Reset();
      g_last = firstEval - 1;
      g_live = false;
      ArrayInitialize(State, 0.0);
      ArrayInitialize(PreEv, 0.0);
      ArrayInitialize(BrkEv, 0.0);
      ObjectsDeleteAll(0, g_prefix);
     }

//--- BW e linee di riferimento (tutte le barre, inclusa la corrente)
   int start = full ? 0 : prev_calculated - 1;
   for(int i = start; i < rates_total && !IsStopped(); i++)
     {
      if(i < firstValid)
        {
         BW[i] = EMPTY_VALUE; LowC[i] = EMPTY_VALUE; HighE[i] = EMPTY_VALUE; Clr[i] = 0;
         continue;
        }
      BW[i] = SqzBandWidth(Up[i], Lo[i], Mid[i]);
      if(i >= firstValid + InpBWLookback - 1)
        {
         double mn = BW[i], mx = BW[i];
         for(int k = 1; k < InpBWLookback; k++)
           {
            mn = MathMin(mn, BW[i - k]);
            mx = MathMax(mx, BW[i - k]);
           }
         LowC[i] = mn; HighE[i] = mx;
        }
      else
        {
         LowC[i] = EMPTY_VALUE; HighE[i] = EMPTY_VALUE;
        }
      if(i == rates_total - 1)
        {
         State[i] = 0.0; PreEv[i] = 0.0; Clr[i] = 0;
        }
     }

//--- macchina a stati sulle barre chiuse
   for(int i = g_last + 1; i <= rates_total - 2 && !IsStopped(); i++)
     {
      SqzEvalResult r;
      SqzEvaluate(Up, Mid, Lo, Ema, AtrKC, Atr, i, false, P, r);

      int pre = TR.OnClosedBar(r, high[i], low[i], Up[i], Lo[i], time[i], P);
      State[i] = TR.ValidSqueeze(P) ? 2.0 : (TR.inSqz || TR.Armed(P)) ? 1.0 : 0.0;
      PreEv[i] = pre;
      Clr[i]   = (State[i] == 2.0) ? 1 : (State[i] == 1.0) ? 2 : 0;

      if(TR.inSqz && InpDrawRange && TR.sqCount >= InpMinBars)
         DrawRange(TR.sqStart, time[i] + PeriodSeconds(_Period), TR.rangeHi, TR.rangeLo);

      if(pre != 0)
        {
         if(InpArrows)
            DrawArrow("pre", time[i], pre > 0 ? low[i] : high[i], pre > 0, false);
         Notify(pre > 0 ? "PRE-ESPLOSIONE LONG" : "PRE-ESPLOSIONE SHORT");
        }

      int brk = TR.OnBarOpen(open[i + 1], Up[i], Lo[i], P);
      BrkEv[i + 1] = brk;
      if(brk != 0)
        {
         if(InpArrows)
            DrawArrow("brk", time[i + 1], open[i + 1], brk > 0, true);
         Notify(brk > 0 ? "BREAKOUT LONG (apertura sopra la banda)" : "BREAKOUT SHORT (apertura sotto la banda)");
        }
      g_last = i;
     }

   g_live = true;
   return rates_total;
  }

//+------------------------------------------------------------------+
void Notify(const string what)
  {
   if(!g_live)
      return;   // niente avvisi sullo storico
   string msg = _Symbol + " " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7) + ": " + what;
   if(InpAlerts) Alert(msg);
   if(InpPush)   SendNotification(msg);
  }

//+------------------------------------------------------------------+
void DrawArrow(const string kind, const datetime t, const double price, const bool up, const bool big)
  {
   string name = g_prefix + kind + "_" + IntegerToString((long)t) + (up ? "_u" : "_d");
   if(ObjectFind(0, name) >= 0)
      return;
   if(!ObjectCreate(0, name, OBJ_ARROW, 0, t, price))
      return;
   int code = big ? (up ? 241 : 242) : (up ? 233 : 234);
   color c  = big ? (up ? clrLime : clrRed) : (up ? clrTeal : clrMaroon);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, big ? 2 : 1);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, up ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, big ? (up ? "BREAKOUT long" : "BREAKOUT short") : (up ? "PRE long" : "PRE short"));
  }

//+------------------------------------------------------------------+
void DrawRange(const datetime t1, const datetime t2, const double hi, const double lo)
  {
   string name = g_prefix + "rng_" + IntegerToString((long)t1);
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGoldenrod);
      ObjectSetInteger(0, name, OBJPROP_FILL, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
   else
     {
      ObjectMove(0, name, 0, t1, hi);
      ObjectMove(0, name, 1, t2, lo);
     }
  }
//+------------------------------------------------------------------+
