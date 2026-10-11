//+------------------------------------------------------------------+
//|                                                    BBSqueeze.mq5 |
//|  Bollinger Squeeze: BandWidth + opzionale filtro Keltner (TTM)   |
//|                                                                  |
//|  Istogramma BandWidth:                                           |
//|    grigio = nessuno squeeze                                      |
//|    rosso  = squeeze attivo                                       |
//|    verde  = prima barra dopo la fine dello squeeze (release)     |
//|  Linea tratteggiata = soglia squeeze (minimo lookback + tolleranza)|
//+------------------------------------------------------------------+
#property copyright   "Dario"
#property version     "1.00"
#property description "Bollinger Squeeze - BandWidth / Keltner"

#property indicator_separate_window
#property indicator_buffers 9
#property indicator_plots   2

#property indicator_label1  "BandWidth"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrSilver,clrRed,clrLime
#property indicator_width1  2

#property indicator_label2  "Soglia squeeze"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#include <BBSqueeze\SqueezeCommon.mqh>

//--- input
input int           InpBBPeriod   = 20;            // Periodo Bollinger
input double        InpBBDev      = 2.0;           // Deviazioni standard
input ENUM_SQZ_MODE InpMode       = SQZ_BANDWIDTH; // Definizione squeeze
input int           InpBWLookback = 125;           // Lookback minimo BandWidth (barre)
input double        InpBWTolPct   = 10.0;          // Tolleranza % sopra il minimo
input int           InpKCPeriod   = 20;            // Periodo Keltner (EMA + ATR)
input double        InpKCMult     = 1.5;           // Moltiplicatore ATR Keltner
input bool          InpAlerts     = false;         // Alert inizio/fine squeeze

//--- buffer
double BW[];      // 0 BandWidth (plot)
double Clr[];     // 1 indice colore
double Thr[];     // 2 soglia (plot)
double Sqz[];     // 3 1 = squeeze, 0 = no  (leggibile via iCustom)
double Up[];      // 4
double Mid[];     // 5
double Lo[];      // 6
double Ema[];     // 7
double Atr[];     // 8

int hBB  = INVALID_HANDLE;
int hEMA = INVALID_HANDLE;
int hATR = INVALID_HANDLE;
datetime g_lastAlertBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBBPeriod < 2 || InpKCPeriod < 2 || InpBWLookback < 2 || InpBBDev <= 0.0 || InpKCMult <= 0.0)
     {
      Print("BBSqueeze: parametri non validi");
      return INIT_PARAMETERS_INCORRECT;
     }

   SetIndexBuffer(0, BW,  INDICATOR_DATA);
   SetIndexBuffer(1, Clr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, Thr, INDICATOR_DATA);
   SetIndexBuffer(3, Sqz, INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, Up,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, Mid, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, Lo,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, Ema, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, Atr, INDICATOR_CALCULATIONS);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   hBB  = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDev, PRICE_CLOSE);
   hEMA = iMA(_Symbol, _Period, InpKCPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hATR = iATR(_Symbol, _Period, InpKCPeriod);
   if(hBB == INVALID_HANDLE || hEMA == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("BBSqueeze: errore creazione handle ", GetLastError());
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("BBSqueeze(%d,%.1f,%s)", InpBBPeriod, InpBBDev, EnumToString(InpMode)));
   IndicatorSetInteger(INDICATOR_DIGITS, 4);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hBB  != INVALID_HANDLE) IndicatorRelease(hBB);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
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
   int firstValid = MathMax(InpBBPeriod, InpKCPeriod);
   if(rates_total < firstValid + InpBWLookback)
      return 0;

   if(BarsCalculated(hBB) < rates_total || BarsCalculated(hEMA) < rates_total || BarsCalculated(hATR) < rates_total)
      return 0;

   int toCopy;
   if(prev_calculated <= 0 || prev_calculated > rates_total)
      toCopy = rates_total;
   else
      toCopy = rates_total - prev_calculated + 1;

   if(CopyBuffer(hBB,  0, 0, toCopy, Mid) <= 0) return 0;   // BASE_LINE
   if(CopyBuffer(hBB,  1, 0, toCopy, Up)  <= 0) return 0;   // UPPER_BAND
   if(CopyBuffer(hBB,  2, 0, toCopy, Lo)  <= 0) return 0;   // LOWER_BAND
   if(CopyBuffer(hEMA, 0, 0, toCopy, Ema) <= 0) return 0;
   if(CopyBuffer(hATR, 0, 0, toCopy, Atr) <= 0) return 0;

   int start = (prev_calculated <= 0) ? 0 : prev_calculated - 1;

   for(int i = start; i < rates_total && !IsStopped(); i++)
     {
      if(i < firstValid)
        {
         BW[i] = EMPTY_VALUE; Thr[i] = EMPTY_VALUE; Sqz[i] = 0.0; Clr[i] = 0;
         continue;
        }

      BW[i] = SqzBandWidth(Up[i], Lo[i], Mid[i]);

      if(i < firstValid + InpBWLookback - 1)
        {
         Thr[i] = EMPTY_VALUE; Sqz[i] = 0.0; Clr[i] = 0;
         continue;
        }

      double mn = BW[i];
      for(int k = 1; k < InpBWLookback; k++)
         if(BW[i - k] < mn)
            mn = BW[i - k];

      Thr[i] = (InpMode == SQZ_KELTNER) ? EMPTY_VALUE : mn * (1.0 + InpBWTolPct / 100.0);

      bool s = SqzEval(BW[i], mn, InpBWTolPct, Up[i], Lo[i], Ema[i], Atr[i], InpKCMult, InpMode);
      Sqz[i] = s ? 1.0 : 0.0;

      if(s)
         Clr[i] = 1;
      else
         Clr[i] = (Sqz[i - 1] > 0.5) ? 2 : 0;
     }

//--- alert solo su barra chiusa, una volta per barra
   if(rates_total >= 3)
     {
      datetime cur = time[rates_total - 1];
      if(prev_calculated <= 0)
         g_lastAlertBar = cur;               // niente alert al caricamento
      else if(InpAlerts && cur != g_lastAlertBar)
        {
         g_lastAlertBar = cur;
         int c = rates_total - 2;            // ultima barra chiusa
         if(Sqz[c] > 0.5 && Sqz[c - 1] < 0.5)
            Alert(_Symbol, " ", EnumToString(_Period), ": inizio squeeze");
         if(Sqz[c] < 0.5 && Sqz[c - 1] > 0.5)
            Alert(_Symbol, " ", EnumToString(_Period), ": fine squeeze (release)");
        }
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
