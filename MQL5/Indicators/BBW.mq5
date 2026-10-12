//+------------------------------------------------------------------+
//|                                                          BBW.mq5 |
//|  Bollinger BandWidth - porting 1:1 dell'indicatore integrato     |
//|  "Bollinger BandWidth" (BBW) di TradingView, Pine v6:            |
//|    basis = SMA(src, length)                                      |
//|    dev   = mult * stdev(src, length)   (deviazione di popolazione,|
//|            come ta.stdev di default)                             |
//|    bbw   = (upper - lower) / basis * 100                         |
//|    Highest Expansion  = massimo di bbw su 125 barre              |
//|    Lowest Contraction = minimo  di bbw su 125 barre              |
//|  Indipendente dagli altri file del progetto.                     |
//+------------------------------------------------------------------+
#property copyright   "Dario"
#property version     "1.00"
#property description "Bollinger BandWidth (BBW) - come TradingView"

#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   3

#property indicator_label1  "Bollinger BandWidth"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'41,98,255'     // #2962FF
#property indicator_width1  1

#property indicator_label2  "Highest Expansion"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'242,54,69'     // #F23645
#property indicator_width2  1

#property indicator_label3  "Lowest Contraction"
#property indicator_type3   DRAW_LINE
#property indicator_color3  C'8,153,129'     // #089981
#property indicator_width3  1

//--- input (stessi nomi e default di TradingView)
input int                InpLength      = 20;           // Length
input ENUM_APPLIED_PRICE InpSource      = PRICE_CLOSE;  // Source
input double             InpMult        = 2.0;          // StdDev
input int                InpExpLength   = 125;          // Highest Expansion Length
input int                InpContrLength = 125;          // Lowest Contraction Length

//--- buffer
double BBWBuf[];
double HiBuf[];
double LoBuf[];
double SrcBuf[];   // prezzo sorgente (calcolo)

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLength < 1 || InpMult < 0.001 || InpMult > 50.0 || InpExpLength < 1 || InpContrLength < 1)
     {
      Print("BBW: parametri non validi");
      return INIT_PARAMETERS_INCORRECT;
     }

   SetIndexBuffer(0, BBWBuf, INDICATOR_DATA);
   SetIndexBuffer(1, HiBuf,  INDICATOR_DATA);
   SetIndexBuffer(2, LoBuf,  INDICATOR_DATA);
   SetIndexBuffer(3, SrcBuf, INDICATOR_CALCULATIONS);

   for(int k = 0; k < 3; k++)
      PlotIndexSetDouble(k, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpLength - 1);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, InpLength + InpExpLength - 2);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, InpLength + InpContrLength - 2);

   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("BBW %d %.1f", InpLength, InpMult));
   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
double PriceOf(const ENUM_APPLIED_PRICE src, const double o, const double h, const double l, const double c)
  {
   switch(src)
     {
      case PRICE_OPEN:     return o;
      case PRICE_HIGH:     return h;
      case PRICE_LOW:      return l;
      case PRICE_MEDIAN:   return (h + l) / 2.0;
      case PRICE_TYPICAL:  return (h + l + c) / 3.0;
      case PRICE_WEIGHTED: return (h + l + 2.0 * c) / 4.0;
      default:             return c;
     }
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
   if(rates_total < InpLength)
      return 0;

   int start = (prev_calculated <= 0 || prev_calculated > rates_total) ? 0 : prev_calculated - 1;

   for(int i = start; i < rates_total && !IsStopped(); i++)
     {
      SrcBuf[i] = PriceOf(InpSource, open[i], high[i], low[i], close[i]);

      //--- BBW
      if(i < InpLength - 1)
        {
         BBWBuf[i] = EMPTY_VALUE;
         HiBuf[i]  = EMPTY_VALUE;
         LoBuf[i]  = EMPTY_VALUE;
         continue;
        }

      double sum = 0.0;
      for(int k = 0; k < InpLength; k++)
         sum += SrcBuf[i - k];
      double basis = sum / InpLength;

      double var = 0.0;
      for(int k = 0; k < InpLength; k++)
        {
         double d = SrcBuf[i - k] - basis;
         var += d * d;
        }
      double dev = InpMult * MathSqrt(var / InpLength);   // popolazione (N)

      BBWBuf[i] = (basis != 0.0) ? (2.0 * dev) / basis * 100.0 : EMPTY_VALUE;

      //--- Highest Expansion / Lowest Contraction
      HiBuf[i] = Extreme(i, InpExpLength, true);
      LoBuf[i] = Extreme(i, InpContrLength, false);
     }

   return rates_total;
  }

//+------------------------------------------------------------------+
//| Massimo/minimo del BBW sulle ultime len barre (servono tutte valide)
//+------------------------------------------------------------------+
double Extreme(const int i, const int len, const bool highest)
  {
   if(i - len + 1 < InpLength - 1)
      return EMPTY_VALUE;
   double v = BBWBuf[i];
   for(int k = 1; k < len; k++)
     {
      double x = BBWBuf[i - k];
      if(x == EMPTY_VALUE)
         return EMPTY_VALUE;
      v = highest ? MathMax(v, x) : MathMin(v, x);
     }
   return v;
  }
//+------------------------------------------------------------------+
