//+------------------------------------------------------------------+
//|                                                  BBSqueezeEA.mq5 |
//|  Expert Advisor: Bollinger Squeeze breakout                      |
//|                                                                  |
//|  Logica (barre chiuse, una valutazione per nuova barra):         |
//|  1. Squeeze = BandWidth vicino al minimo di N barre e/o BB       |
//|     dentro Keltner (stessa logica dell'indicatore BBSqueeze).    |
//|  2. Episodio valido se dura almeno InpMinSqueezeBars barre;      |
//|     si registrano max/min delle barre di squeeze.                |
//|  3. Setup armato durante lo squeeze valido e per InpArmedBars    |
//|     barre dopo la sua fine.                                      |
//|  4. Ingresso:                                                    |
//|     - CLOSE_BREAKOUT: chiusura oltre la banda (e opz. oltre      |
//|       max/min squeeze) -> ordine a mercato all'apertura succ.    |
//|     - PENDING_OCO: buy stop su max, sell stop su min dello       |
//|       squeeze; quando uno scatta l'altro viene cancellato.       |
//|  5. SL oltre il lato opposto del range di squeeze (+ buffer ATR).|
//|  6. TP: multiplo dell'altezza del range, R:R, oppure nessuno.    |
//|  7. Trailing opzionale: banda centrale o ATR.                    |
//|  Un solo trade per episodio di squeeze.                          |
//+------------------------------------------------------------------+
#property copyright   "Dario"
#property version     "1.00"
#property description "Bollinger Squeeze breakout EA"

#include <Trade\Trade.mqh>
#include <BBSqueeze\SqueezeCommon.mqh>

enum ENUM_ENTRY_MODE
  {
   ENTRY_CLOSE_BREAKOUT = 0, // Chiusura fuori banda -> mercato
   ENTRY_PENDING_OCO    = 1  // Stop order OCO su max/min squeeze
  };

enum ENUM_TP_MODE
  {
   TP_NONE       = 0, // Nessun TP
   TP_RANGE_MULT = 1, // Multiplo altezza range squeeze
   TP_RR         = 2  // Multiplo del rischio (R:R)
  };

enum ENUM_TRAIL_MODE
  {
   TRAIL_NONE        = 0, // Nessun trailing
   TRAIL_MIDDLE_BAND = 1, // Banda centrale Bollinger
   TRAIL_ATR         = 2  // Chiusura -/+ ATR x mult
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED    = 0, // Lotto fisso
   LOT_RISK_PCT = 1  // % del balance a rischio
  };

//--- input
input group "Bollinger / Squeeze"
input int             InpBBPeriod          = 20;            // Periodo Bollinger
input double          InpBBDev             = 2.0;           // Deviazioni standard
input ENUM_SQZ_MODE   InpSqzMode           = SQZ_BANDWIDTH; // Definizione squeeze
input int             InpBWLookback        = 125;           // Lookback minimo BandWidth (barre)
input double          InpBWTolPct          = 10.0;          // Tolleranza % sopra il minimo
input int             InpKCPeriod          = 20;            // Periodo Keltner (EMA + ATR)
input double          InpKCMult            = 1.5;           // Moltiplicatore ATR Keltner
input int             InpMinSqueezeBars    = 5;             // Durata minima squeeze (barre)
input int             InpArmedBars         = 3;             // Barre valide dopo fine squeeze

input group "Ingresso"
input ENUM_ENTRY_MODE InpEntryMode         = ENTRY_CLOSE_BREAKOUT; // Modalità ingresso
input bool            InpRequireRangeBreak = true;          // CLOSE: chiusura anche oltre max/min squeeze
input double          InpEntryBufferATR    = 0.0;           // PENDING: buffer oltre max/min (x ATR)
input bool            InpAllowLong         = true;          // Abilita long
input bool            InpAllowShort        = true;          // Abilita short
input int             InpMaxSpreadPts      = 0;             // Spread massimo in punti (0 = off)

input group "Stop / Target"
input double          InpSLBufferATR       = 0.1;           // Buffer SL oltre il range (x ATR)
input double          InpMaxSL_ATR         = 3.0;           // SL massimo (x ATR, 0 = off)
input ENUM_TP_MODE    InpTPMode            = TP_RANGE_MULT; // Modalità TP
input double          InpTPRangeMult       = 1.0;           // TP = altezza range x
input double          InpTPRR              = 2.0;           // TP = rischio x
input ENUM_TRAIL_MODE InpTrailMode         = TRAIL_NONE;    // Trailing stop
input double          InpTrailATRMult      = 2.0;           // Trailing ATR x

input group "Size"
input ENUM_LOT_MODE   InpLotMode           = LOT_RISK_PCT;  // Calcolo lotto
input double          InpFixedLots         = 0.10;          // Lotto fisso
input double          InpRiskPct           = 0.5;           // Rischio % del balance

input group "Varie"
input ulong           InpMagic             = 20261011;      // Magic number
input bool            InpDrawRange         = true;          // Disegna rettangolo squeeze
input int             InpReplayBars        = 300;           // Barre per ricostruire lo stato all'avvio

//--- handle e dati
int    hBB = INVALID_HANDLE, hEMA = INVALID_HANDLE, hATR = INVALID_HANDLE;
double bUp[], bMid[], bLo[], bEma[], bAtr[];
MqlRates rt[];
CTrade trade;

//--- stato episodio di squeeze
bool     g_ready    = false;
datetime g_lastBar  = 0;
bool     g_inSq     = false;  // squeeze in corso
int      g_sqBars   = 0;      // durata squeeze corrente/ultimo
double   g_hi       = 0.0;    // massimo range squeeze
double   g_lo       = 0.0;    // minimo range squeeze
datetime g_sqStart  = 0;
datetime g_sqEnd    = 0;
int      g_postBars = -1;     // barre trascorse dalla fine (-1 = nessun setup post-squeeze)
bool     g_used     = false;  // trade già preso su questo episodio
double   g_pendHi   = 0.0;    // livelli a cui sono stati piazzati i pending
double   g_pendLo   = 0.0;

const string OBJ_PREFIX = "BBSqz_";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBBPeriod < 2 || InpKCPeriod < 2 || InpBWLookback < 2 || InpMinSqueezeBars < 1 ||
      InpArmedBars < 0 || InpBBDev <= 0.0 || InpKCMult <= 0.0 || InpRiskPct <= 0.0 || InpFixedLots <= 0.0)
     {
      Print("BBSqueezeEA: parametri non validi");
      return INIT_PARAMETERS_INCORRECT;
     }

   hBB  = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDev, PRICE_CLOSE);
   hEMA = iMA(_Symbol, _Period, InpKCPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hATR = iATR(_Symbol, _Period, InpKCPeriod);
   if(hBB == INVALID_HANDLE || hEMA == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("BBSqueezeEA: errore creazione handle ", GetLastError());
      return INIT_FAILED;
     }

   ArraySetAsSeries(bUp, true);
   ArraySetAsSeries(bMid, true);
   ArraySetAsSeries(bLo, true);
   ArraySetAsSeries(bEma, true);
   ArraySetAsSeries(bAtr, true);
   ArraySetAsSeries(rt, true);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   g_ready   = false;
   g_lastBar = 0;
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hBB  != INVALID_HANDLE) IndicatorRelease(hBB);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(reason == REASON_REMOVE)
      ObjectsDeleteAll(0, OBJ_PREFIX);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
//--- OCO: se c'è una posizione, niente pending residui e episodio consumato
   if(InpEntryMode == ENTRY_PENDING_OCO && CountPositions() > 0)
     {
      g_used = true;
      if(CountPendings() > 0)
         DeletePendings();
     }

   datetime t = iTime(_Symbol, _Period, 0);
   if(t == 0 || t == g_lastBar)
      return;

//--- prima esecuzione: ricostruisce lo stato senza tradare
   if(!g_ready)
     {
      int avail  = Bars(_Symbol, _Period);
      int replay = MathMin(InpReplayBars, avail - InpBWLookback - 3);
      if(replay < 1)
         return;
      if(!LoadData(replay + InpBWLookback + 2))
         return;
      for(int s = replay; s >= 1; s--)
         ProcessBar(s, false);
      g_ready   = true;
      g_lastBar = t;
      ManagePending();
      return;
     }

   if(!LoadData(InpBWLookback + 3))
      return;
   g_lastBar = t;

   ProcessBar(1, true);
   ManageTrailing();
   ManagePending();
  }

//+------------------------------------------------------------------+
//| Copia dati (serie: indice 0 = barra corrente)                     |
//+------------------------------------------------------------------+
bool LoadData(const int bars)
  {
   if(BarsCalculated(hBB) < bars || BarsCalculated(hEMA) < bars || BarsCalculated(hATR) < bars)
      return false;
   if(CopyBuffer(hBB, 1, 0, bars, bUp)  != bars) return false;
   if(CopyBuffer(hBB, 0, 0, bars, bMid) != bars) return false;
   if(CopyBuffer(hBB, 2, 0, bars, bLo)  != bars) return false;
   if(CopyBuffer(hEMA, 0, 0, bars, bEma) != bars) return false;
   if(CopyBuffer(hATR, 0, 0, bars, bAtr) != bars) return false;
   if(CopyRates(_Symbol, _Period, 0, bars, rt) != bars) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Squeeze sulla barra s (richiede s + lookback - 1 barre copiate)   |
//+------------------------------------------------------------------+
bool IsSqueeze(const int s)
  {
   double bw = SqzBandWidth(bUp[s], bLo[s], bMid[s]);
   double mn = bw;
   for(int k = 1; k < InpBWLookback; k++)
     {
      double v = SqzBandWidth(bUp[s + k], bLo[s + k], bMid[s + k]);
      if(v < mn)
         mn = v;
     }
   return SqzEval(bw, mn, InpBWTolPct, bUp[s], bLo[s], bEma[s], bAtr[s], InpKCMult, InpSqzMode);
  }

//+------------------------------------------------------------------+
bool SetupArmed()
  {
   if(g_used)
      return false;
   if(g_inSq && g_sqBars >= InpMinSqueezeBars)
      return true;
   return (g_postBars >= 1);
  }

//+------------------------------------------------------------------+
//| Aggiorna lo stato con la barra chiusa s; eventualmente entra      |
//+------------------------------------------------------------------+
void ProcessBar(const int s, const bool allowTrade)
  {
   bool sq = IsSqueeze(s);

//--- fine squeeze / avanzamento finestra post-squeeze
   if(!sq)
     {
      if(g_inSq)
        {
         g_inSq     = false;
         g_postBars = (g_sqBars >= InpMinSqueezeBars) ? 1 : -1;
        }
      else if(g_postBars >= 0)
        {
         g_postBars++;
         if(g_postBars > InpArmedBars)
            g_postBars = -1;
        }
     }

//--- breakout in chiusura (il range NON include ancora la barra s)
   if(InpEntryMode == ENTRY_CLOSE_BREAKOUT && SetupArmed())
     {
      double c   = rt[s].close;
      int    dir = 0;
      if(InpAllowLong && c > bUp[s] && (!InpRequireRangeBreak || c > g_hi))
         dir = 1;
      else if(InpAllowShort && c < bLo[s] && (!InpRequireRangeBreak || c < g_lo))
         dir = -1;

      if(dir != 0)
        {
         g_used = true;   // un tentativo per episodio, anche se l'ordine viene scartato dai filtri
         if(allowTrade)
            OpenMarket(dir, s);
        }
     }

//--- squeeze in corso: inizio episodio o estensione del range
   if(sq)
     {
      if(!g_inSq)
        {
         g_inSq     = true;
         g_sqBars   = 0;
         g_hi       = rt[s].high;
         g_lo       = rt[s].low;
         g_sqStart  = rt[s].time;
         g_postBars = -1;
         g_used     = false;
        }
      g_sqBars++;
      g_hi    = MathMax(g_hi, rt[s].high);
      g_lo    = MathMin(g_lo, rt[s].low);
      g_sqEnd = rt[s].time;

      if(InpDrawRange && g_sqBars >= InpMinSqueezeBars)
         DrawRange();
     }
  }

//+------------------------------------------------------------------+
void OpenMarket(const int dir, const int s)
  {
   if(CountPositions() > 0)
      return;
   if(!SpreadOK())
      return;

   double atr   = bAtr[s];
   double entry = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl    = (dir > 0) ? g_lo - InpSLBufferATR * atr : g_hi + InpSLBufferATR * atr;
   double tp, lots;
   if(!PrepareOrder(dir, entry, sl, tp, lots, atr))
      return;

   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, 0.0, sl, tp, "BBSqz")
                       : trade.Sell(lots, _Symbol, 0.0, sl, tp, "BBSqz");
   if(!ok)
      PrintFormat("BBSqueezeEA: ordine a mercato fallito, retcode %u (%s)",
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Gestione stop order OCO                                           |
//+------------------------------------------------------------------+
void ManagePending()
  {
   if(InpEntryMode != ENTRY_PENDING_OCO)
      return;

   if(CountPositions() > 0)
     {
      g_used = true;
      DeletePendings();
      return;
     }

   if(!SetupArmed())
     {
      if(CountPendings() > 0)
         DeletePendings();
      return;
     }

//--- già piazzati agli stessi livelli -> niente da fare
   int expected = (InpAllowLong ? 1 : 0) + (InpAllowShort ? 1 : 0);
   if(CountPendings() == expected && g_pendHi == g_hi && g_pendLo == g_lo)
      return;

   DeletePendings();
   if(!SpreadOK())
      return;

   double atr     = bAtr[1];
   double buf     = InpEntryBufferATR * atr;
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   if(InpAllowLong)
     {
      double px = NormalizePrice(g_hi + buf);
      if(px > ask + minDist)
        {
         double sl = g_lo - InpSLBufferATR * atr, tp, lots;
         if(PrepareOrder(1, px, sl, tp, lots, atr))
            if(!trade.BuyStop(lots, px, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "BBSqz"))
               PrintFormat("BBSqueezeEA: BuyStop fallito, retcode %u", trade.ResultRetcode());
        }
     }

   if(InpAllowShort)
     {
      double px = NormalizePrice(g_lo - buf);
      if(px < bid - minDist)
        {
         double sl = g_hi + InpSLBufferATR * atr, tp, lots;
         if(PrepareOrder(-1, px, sl, tp, lots, atr))
            if(!trade.SellStop(lots, px, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "BBSqz"))
               PrintFormat("BBSqueezeEA: SellStop fallito, retcode %u", trade.ResultRetcode());
        }
     }

   g_pendHi = g_hi;
   g_pendLo = g_lo;
  }

//+------------------------------------------------------------------+
//| Calcola SL/TP normalizzati e lotti; false = trade da scartare     |
//+------------------------------------------------------------------+
bool PrepareOrder(const int dir, const double entry, double &sl, double &tp, double &lots, const double atr)
  {
   sl = NormalizePrice(sl);
   double dist = (dir > 0) ? entry - sl : sl - entry;
   if(dist <= 0.0)
      return false;

   if(InpMaxSL_ATR > 0.0 && dist > InpMaxSL_ATR * atr)
     {
      PrintFormat("BBSqueezeEA: SL %.1f ATR > max %.1f, trade scartato", dist / atr, InpMaxSL_ATR);
      return false;
     }

   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dist < minDist)
      return false;

   double height = g_hi - g_lo;
   tp = 0.0;
   if(InpTPMode == TP_RANGE_MULT)
      tp = (dir > 0) ? entry + height * InpTPRangeMult : entry - height * InpTPRangeMult;
   else if(InpTPMode == TP_RR)
      tp = (dir > 0) ? entry + dist * InpTPRR : entry - dist * InpTPRR;
   if(tp != 0.0)
      tp = NormalizePrice(tp);

   lots = CalcLots(dist);
   return (lots > 0.0);
  }

//+------------------------------------------------------------------+
double CalcLots(const double dist)
  {
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      return 0.0;

   double lots = InpFixedLots;
   if(InpLotMode == LOT_RISK_PCT)
     {
      double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tv <= 0.0)
         tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tv <= 0.0 || ts <= 0.0)
         return 0.0;
      double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
      double lossPerLot = dist / ts * tv;
      if(lossPerLot <= 0.0)
         return 0.0;
      lots = riskMoney / lossPerLot;
     }

   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < minL)
     {
      PrintFormat("BBSqueezeEA: lotto %.4f < minimo %.2f, trade scartato (non aumento il rischio)", lots, minL);
      return 0.0;
     }
   lots = MathMin(lots, maxL);

   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(lots, digits);
  }

//+------------------------------------------------------------------+
void ManageTrailing()
  {
   if(InpTrailMode == TRAIL_NONE)
      return;

   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double newSl;

      if(InpTrailMode == TRAIL_MIDDLE_BAND)
         newSl = bMid[1];
      else
         newSl = (type == POSITION_TYPE_BUY) ? rt[1].close - InpTrailATRMult * bAtr[1]
                                             : rt[1].close + InpTrailATRMult * bAtr[1];
      newSl = NormalizePrice(newSl);

      if(type == POSITION_TYPE_BUY)
        {
         if((sl == 0.0 || newSl > sl) && newSl < bid - minDist)
            trade.PositionModify(ticket, newSl, tp);
        }
      else
        {
         if((sl == 0.0 || newSl < sl) && newSl > ask + minDist)
            trade.PositionModify(ticket, newSl, tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Utility                                                           |
//+------------------------------------------------------------------+
double NormalizePrice(const double p)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0)
      return NormalizeDouble(p, _Digits);
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
  }

bool SpreadOK()
  {
   if(InpMaxSpreadPts <= 0)
      return true;
   long spr = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spr > InpMaxSpreadPts)
     {
      PrintFormat("BBSqueezeEA: spread %d > max %d, ingresso saltato", (int)spr, InpMaxSpreadPts);
      return false;
     }
   return true;
  }

int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) == (long)InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
         n++;
     }
   return n;
  }

int CountPendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) == (long)InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
         n++;
     }
   return n;
  }

void DeletePendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) == (long)InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
         trade.OrderDelete(ticket);
     }
   g_pendHi = 0.0;
   g_pendLo = 0.0;
  }

void DrawRange()
  {
   string name = OBJ_PREFIX + IntegerToString((long)g_sqStart);
   datetime tEnd = g_sqEnd + PeriodSeconds(_Period);
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, g_sqStart, g_hi, tEnd, g_lo);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGoldenrod);
      ObjectSetInteger(0, name, OBJPROP_FILL, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
   else
     {
      ObjectMove(0, name, 0, g_sqStart, g_hi);
      ObjectMove(0, name, 1, tEnd, g_lo);
     }
  }
//+------------------------------------------------------------------+
