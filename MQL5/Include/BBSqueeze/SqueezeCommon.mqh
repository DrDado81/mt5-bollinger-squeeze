//+------------------------------------------------------------------+
//|                                              SqueezeCommon.mqh   |
//|  Logica condivisa tra indicatore BBSqueeze ed EA BBSqueezeEA     |
//+------------------------------------------------------------------+
#ifndef BBSQUEEZE_COMMON_MQH
#define BBSQUEEZE_COMMON_MQH

//--- Come si definisce lo squeeze
enum ENUM_SQZ_MODE
  {
   SQZ_BANDWIDTH = 0, // BandWidth vicino al minimo del lookback
   SQZ_KELTNER   = 1, // Bande di Bollinger dentro il Keltner (TTM)
   SQZ_BOTH      = 2  // Entrambe le condizioni
  };

//+------------------------------------------------------------------+
//| BandWidth = (Upper - Lower) / Middle * 100                        |
//+------------------------------------------------------------------+
double SqzBandWidth(const double up, const double lo, const double mid)
  {
   if(mid == 0.0)
      return 0.0;
   return (up - lo) / mid * 100.0;
  }

//+------------------------------------------------------------------+
//| Valuta lo squeeze su una singola barra.                           |
//| bw      : BandWidth della barra                                   |
//| bwMin   : minimo del BandWidth nel lookback (barra inclusa)       |
//| tolPct  : tolleranza % sopra il minimo (10 = entro +10%)          |
//| up/lo   : bande di Bollinger della barra                          |
//| ema/atr : centro e ATR del canale di Keltner                      |
//+------------------------------------------------------------------+
bool SqzEval(const double bw, const double bwMin, const double tolPct,
             const double up, const double lo,
             const double ema, const double atr,
             const double kcMult, const ENUM_SQZ_MODE mode)
  {
   bool bwOk = (bwMin > 0.0 && bw <= bwMin * (1.0 + tolPct / 100.0));
   bool kcOk = (atr > 0.0 && up < ema + kcMult * atr && lo > ema - kcMult * atr);

   if(mode == SQZ_BANDWIDTH)
      return bwOk;
   if(mode == SQZ_KELTNER)
      return kcOk;
   return (bwOk && kcOk);
  }

#endif
//+------------------------------------------------------------------+
