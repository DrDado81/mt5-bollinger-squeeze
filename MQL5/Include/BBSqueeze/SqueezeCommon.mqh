//+------------------------------------------------------------------+
//|                                              SqueezeCommon.mqh   |
//|  Logica condivisa: indicatore, dashboard ed EA usano SOLO questa |
//|                                                                  |
//|  Fasi (stesse dello script TradingView):                         |
//|   SQUEEZE  : BW vicino al minimo del lookback (+ BW piatto,      |
//|              + media centrale piatta, opzionali)                 |
//|   PRONTO   : squeeze valido appena finito (armBars barre)        |
//|   PRE      : dopo/durante lo squeeze valido, candela chiusa      |
//|              sulla banda e BW in salita                          |
//|   BREAKOUT : entro confBars barre dal PRE, una candela APRE      |
//|              oltre la banda della barra precedente               |
//+------------------------------------------------------------------+
#ifndef BBSQUEEZE_COMMON_MQH
#define BBSQUEEZE_COMMON_MQH

//--- Definizione base dello squeeze
enum ENUM_SQZ_MODE
  {
   SQZ_BANDWIDTH = 0, // BandWidth vicino al minimo del lookback
   SQZ_KELTNER   = 1, // Bande di Bollinger dentro il Keltner (TTM)
   SQZ_BOTH      = 2  // Entrambe le condizioni
  };

//--- Parametri condivisi
struct SqzParams
  {
   int               bbPeriod;    // periodo Bollinger
   double            bbDev;       // deviazioni
   ENUM_SQZ_MODE     mode;        // definizione base
   int               bwLookback;  // barre per il minimo del BW
   double            bwTolPct;    // tolleranza % sopra il minimo
   int               kcPeriod;    // Keltner: EMA + ATR
   double            kcMult;
   bool              useFlat;     // BW piatto
   int               flatBars;
   double            flatMax;     // (max-min)/media del BW
   bool              useSlope;    // media centrale piatta
   int               atrPeriod;   // ATR per pendenza
   double            slopeMax;    // |mid - mid[flatBars]| / ATR
   int               minBars;     // durata minima squeeze
   int               armBars;     // barre valide dopo la fine
   double            touchTol;    // tolleranza tocco banda (frazione ampiezza)
   int               riseBars;    // BW in salita
   int               confBars;    // barre utili per la conferma
  };

//--- Esito della valutazione di una barra
struct SqzEvalResult
  {
   bool              sqz;
   bool              bwRising;
   double            bw;
   double            bwMin;
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
//| Condizione base (usata anche dall'EA v1)                          |
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

//+------------------------------------------------------------------+
//| Barre di storia necessarie per valutare una barra                 |
//+------------------------------------------------------------------+
int SqzBarsNeeded(const SqzParams &p)
  {
   return MathMax(p.bwLookback, MathMax(p.flatBars + 1, p.riseBars + 1)) + 1;
  }

//--- indice della barra k posizioni più vecchia
int SqzOlder(const int i, const int k, const bool series)
  {
   return series ? i + k : i - k;
  }

//+------------------------------------------------------------------+
//| Valuta la barra i.                                                |
//| series=true : array a serie (0 = barra corrente)                  |
//| series=false: array cronologici (buffer indicatore)               |
//| atrKC = ATR del Keltner, atr = ATR per la pendenza                |
//+------------------------------------------------------------------+
void SqzEvaluate(const double &up[], const double &mid[], const double &lo[],
                 const double &ema[], const double &atrKC[], const double &atr[],
                 const int i, const bool series, const SqzParams &p, SqzEvalResult &r)
  {
   r.bw = SqzBandWidth(up[i], lo[i], mid[i]);

//--- minimo del BW nel lookback (barra inclusa)
   double mn = r.bw;
   for(int k = 1; k < p.bwLookback; k++)
     {
      int j = SqzOlder(i, k, series);
      double v = SqzBandWidth(up[j], lo[j], mid[j]);
      if(v < mn)
         mn = v;
     }
   r.bwMin = mn;

   bool base = SqzEval(r.bw, mn, p.bwTolPct, up[i], lo[i], ema[i], atrKC[i], p.kcMult, p.mode);

//--- BW piatto
   bool flatOk = true;
   if(p.useFlat)
     {
      double hi = r.bw, lw = r.bw, sum = r.bw;
      for(int k = 1; k < p.flatBars; k++)
        {
         int j = SqzOlder(i, k, series);
         double v = SqzBandWidth(up[j], lo[j], mid[j]);
         hi  = MathMax(hi, v);
         lw  = MathMin(lw, v);
         sum += v;
        }
      double mean = sum / p.flatBars;
      flatOk = (mean > 0.0 && (hi - lw) / mean <= p.flatMax);
     }

//--- media centrale piatta
   bool slopeOk = true;
   if(p.useSlope)
     {
      int j = SqzOlder(i, p.flatBars, series);
      slopeOk = (atr[i] > 0.0 && MathAbs(mid[i] - mid[j]) / atr[i] <= p.slopeMax);
     }

   r.sqz = (base && flatOk && slopeOk);

//--- BW in salita: maggiore di tutti i valori delle riseBars barre precedenti
   bool rising = true;
   for(int k = 1; k <= p.riseBars; k++)
     {
      int j = SqzOlder(i, k, series);
      if(!(r.bw > SqzBandWidth(up[j], lo[j], mid[j])))
        {
         rising = false;
         break;
        }
     }
   r.bwRising = rising;
  }

//+------------------------------------------------------------------+
//| Macchina a stati per un simbolo.                                  |
//| Per ogni nuova barra: OnClosedBar(barra appena chiusa), poi       |
//| OnBarOpen(apertura della barra nuova, bande della barra chiusa).  |
//+------------------------------------------------------------------+
struct SqzTracker
  {
   bool              inSqz;
   int               sqCount;      // barre consecutive di squeeze
   int               lastLen;      // durata dell'ultimo squeeze concluso
   int               barsSince;    // barre dalla fine di uno squeeze valido (-1 = nessuno)
   bool              usedLong;     // PRE long già dato in questo episodio
   bool              usedShort;
   int               preLongAge;   // barre chiuse dal PRE long (-1 = nessuno in attesa)
   int               preShortAge;
   double            rangeHi;      // max/min delle barre di squeeze
   double            rangeLo;
   datetime          sqStart;
   datetime          sqEnd;
   int               lastEvent;    // +-2 PRE, +-3 BREAKOUT, 0 nessuno
   int               lastEventAge; // barre chiuse dall'ultimo evento (-1 = nessuno)

   void              Reset()
     {
      inSqz = false; sqCount = 0; lastLen = 0; barsSince = -1;
      usedLong = false; usedShort = false;
      preLongAge = -1; preShortAge = -1;
      rangeHi = 0.0; rangeLo = 0.0; sqStart = 0; sqEnd = 0;
      lastEvent = 0; lastEventAge = -1;
     }

   bool              ValidSqueeze(const SqzParams &p) const { return (inSqz && sqCount >= p.minBars); }
   bool              Armed(const SqzParams &p) const        { return (ValidSqueeze(p) || barsSince >= 1); }

   //--- barra chiusa: ritorna +2 / -2 se dà un PRE, altrimenti 0
   int               OnClosedBar(const SqzEvalResult &r, const double high, const double low,
                                 const double up, const double lo, const datetime t, const SqzParams &p)
     {
      //--- invecchiamento
      if(lastEventAge >= 0) lastEventAge++;
      if(preLongAge >= 0)   { preLongAge++;  if(preLongAge >= p.confBars)  preLongAge = -1; }
      if(preShortAge >= 0)  { preShortAge++; if(preShortAge >= p.confBars) preShortAge = -1; }

      //--- fine squeeze / finestra post-squeeze
      if(!r.sqz)
        {
         if(inSqz)
           {
            inSqz     = false;
            lastLen   = sqCount;
            barsSince = (sqCount >= p.minBars) ? 1 : -1;
            sqCount   = 0;
           }
         else if(barsSince >= 1)
           {
            barsSince++;
            if(barsSince > p.armBars)
               barsSince = -1;
           }
        }
      else
        {
         if(!inSqz)
           {
            inSqz     = true;
            sqCount   = 0;
            usedLong  = false;
            usedShort = false;
            barsSince = -1;
            rangeHi   = high;
            rangeLo   = low;
            sqStart   = t;
           }
         sqCount++;
         rangeHi = MathMax(rangeHi, high);
         rangeLo = MathMin(rangeLo, low);
         sqEnd   = t;
        }

      //--- PRE
      int ev = 0;
      if(Armed(p) && r.bwRising)
        {
         double width = up - lo;
         if(!usedLong && high >= up - p.touchTol * width)
           {
            usedLong = true; preLongAge = 0; ev = 2;
            lastEvent = 2; lastEventAge = 0;
           }
         if(!usedShort && low <= lo + p.touchTol * width)
           {
            usedShort = true; preShortAge = 0;
            if(ev == 0) ev = -2;
            lastEvent = -2; lastEventAge = 0;
           }
        }
      return ev;
     }

   //--- apertura nuova barra: ritorna +3 / -3 se conferma il breakout
   int               OnBarOpen(const double open, const double upPrev, const double loPrev, const SqzParams &p)
     {
      int ev = 0;
      if(preLongAge >= 0 && open > upPrev)
        {
         preLongAge = -1; ev = 3;
         lastEvent = 3; lastEventAge = 0;
        }
      if(preShortAge >= 0 && open < loPrev)
        {
         preShortAge = -1;
         if(ev == 0) ev = -3;
         lastEvent = -3; lastEventAge = 0;
        }
      return ev;
     }
  };

#endif
//+------------------------------------------------------------------+
