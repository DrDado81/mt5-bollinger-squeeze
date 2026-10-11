//+------------------------------------------------------------------+
//|                                           BBSqueezeDashboard.mq5 |
//|  Dashboard multi-simbolo: squeeze -> PRE -> BREAKOUT             |
//|  Stessa logica dell'indicatore BBSqueeze (SqueezeCommon.mqh).    |
//|                                                                  |
//|  Colonne: Simbolo (clic = apre il grafico) | Fase | Barre di     |
//|  squeeze | BW sopra il minimo | ADR % | Spread/ADR %             |
//|  Ordine: BREAKOUT, PRE, SQUEEZE, PRONTO, VICINO; a parità di     |
//|  fase prima i simboli con costo (spread/ADR) più basso.          |
//+------------------------------------------------------------------+
#property copyright   "Dario"
#property version     "1.00"
#property description "Dashboard Bollinger Squeeze multi-simbolo"

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <BBSqueeze\SqueezeCommon.mqh>

enum ENUM_DASH_POS
  {
   POS_TL = 0, // In alto a sinistra
   POS_TR = 1, // In alto a destra
   POS_BL = 2, // In basso a sinistra
   POS_BR = 3  // In basso a destra
  };

enum ENUM_CLICK_ACTION
  {
   CLICK_SWITCH = 0, // Cambia il simbolo di questo grafico
   CLICK_NEW    = 1  // Apri un nuovo grafico
  };

//--- input
input group "Simboli"
input string          InpSymbols    = "AUDCAD,AUDCHF,AUDJPY,AUDNZD,AUDUSD,CADCHF,CADJPY,CHFJPY,EURAUD,EURCAD,EURCHF,EURGBP,EURJPY,EURNZD,EURUSD,GBPAUD,GBPCAD,GBPCHF,GBPJPY,GBPNZD,GBPUSD,NZDCAD,NZDCHF,NZDJPY,NZDUSD,USDCAD,USDCHF,USDJPY,XAUUSD,GER40"; // Simboli (separati da virgola)
input string          InpSuffix     = "";               // Suffisso broker (es. .r, m)
input ENUM_TIMEFRAMES InpTF         = PERIOD_CURRENT;   // Timeframe di analisi

input group "Bollinger / Squeeze"
input int             InpBBPeriod   = 20;            // Periodo Bollinger
input double          InpBBDev      = 2.0;           // Deviazioni standard
input ENUM_SQZ_MODE   InpMode       = SQZ_BANDWIDTH; // Definizione base squeeze
input int             InpBWLookback = 125;           // Lookback minimo BW (barre)
input double          InpBWTolPct   = 10.0;          // Tolleranza % sopra il minimo
input int             InpKCPeriod   = 20;            // Keltner: periodo EMA + ATR
input double          InpKCMult     = 1.5;           // Keltner: moltiplicatore ATR
input bool            InpUseFlat    = true;          // Richiedi BW piatto
input int             InpFlatBars   = 10;            // Barre per piattezza
input double          InpFlatMax    = 0.15;          // Escursione max BW (frazione della media)
input bool            InpUseSlope   = true;          // Richiedi bande piatte
input int             InpATRPeriod  = 14;            // ATR per la pendenza
input double          InpSlopeMax   = 1.0;           // Pendenza max media centrale (x ATR)
input int             InpMinBars    = 5;             // Durata minima squeeze (barre)

input group "Segnali"
input int             InpArmBars    = 10;            // Barre valide dopo la fine dello squeeze
input double          InpTouchTol   = 0.10;          // Tolleranza tocco banda
input int             InpRiseBars   = 2;             // Barre di BW in salita
input int             InpConfBars   = 5;             // Barre utili per la conferma

input group "Dashboard"
input bool            InpOnlyActive = true;          // Mostra solo simboli attivi
input bool            InpShowNear   = false;         // Mostra anche i simboli VICINI allo squeeze
input double          InpNearPct    = 25.0;          // Soglia VICINO (% sopra il minimo BW)
input int             InpEvMaxAge   = 3;             // Mostra PRE/BREAKOUT delle ultime N barre
input int             InpAdrDays    = 20;            // Giorni per ADR
input int             InpSpreadBars = 100;           // Barre per lo spread medio
input int             InpReplayBars = 300;           // Barre per ricostruire lo stato all'avvio
input ENUM_DASH_POS   InpPos        = POS_TL;        // Posizione
input int             InpX          = 10;            // Margine orizzontale (px)
input int             InpY          = 25;            // Margine verticale (px)
input int             InpFontSize   = 8;             // Dimensione testo
input bool            InpLegend     = true;          // Mostra legenda
input ENUM_CLICK_ACTION InpClick    = CLICK_SWITCH;  // Clic sul simbolo
input int             InpTimerSec   = 5;             // Aggiornamento (secondi)

input group "Avvisi"
input bool            InpAlerts     = false;         // Alert popup su PRE / BREAKOUT
input bool            InpPush       = false;         // Notifiche push (app MT5)

//--- stato per simbolo
struct SymInfo
  {
   string            name;      // nome visualizzato
   string            sym;       // nome sul broker
   bool              ok;        // simbolo e handle validi
   int               hBB, hEMA, hATRkc, hATR;
   bool              ready;     // stato ricostruito
   datetime          lastBar;   // apertura della barra corrente all'ultimo aggiornamento
   SqzTracker        tr;
   double            bwPct;     // BW sopra il minimo, %
   double            adrPct;    // ADR in % del prezzo
   double            costPct;   // spread medio / ADR, %
  };

SymInfo         S[];
SqzParams       P;
ENUM_TIMEFRAMES g_tf;
int             g_rowSym[];       // riga -> indice simbolo
int             g_prevRows = 0;
const string    PFX = "BBSqzD_";

//--- colonne
const int NCOL = 6;
string    COL_TITLE[6] = {"Simbolo", "Fase", "Barre", "BW vs min", "ADR %", "Spread/ADR"};
int       COL_W[6]     = {70, 120, 45, 70, 55, 75};

//+------------------------------------------------------------------+
int OnInit()
  {
   P.bbPeriod = InpBBPeriod;   P.bbDev = InpBBDev;       P.mode = InpMode;
   P.bwLookback = InpBWLookback; P.bwTolPct = InpBWTolPct;
   P.kcPeriod = InpKCPeriod;   P.kcMult = InpKCMult;
   P.useFlat = InpUseFlat;     P.flatBars = InpFlatBars; P.flatMax = InpFlatMax;
   P.useSlope = InpUseSlope;   P.atrPeriod = InpATRPeriod; P.slopeMax = InpSlopeMax;
   P.minBars = InpMinBars;     P.armBars = InpArmBars;
   P.touchTol = InpTouchTol;   P.riseBars = InpRiseBars; P.confBars = InpConfBars;

   if(P.bbPeriod < 2 || P.bwLookback < 2 || P.flatBars < 2 || P.riseBars < 1 || P.confBars < 1 || P.minBars < 1)
     {
      Print("BBSqueezeDashboard: parametri non validi");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_tf = (InpTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpTF;

   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   ArrayResize(S, 0);
   for(int k = 0; k < n; k++)
     {
      string nm = parts[k];
      StringTrimLeft(nm);
      StringTrimRight(nm);
      if(nm == "")
         continue;
      int i = ArraySize(S);
      ArrayResize(S, i + 1);
      S[i].name    = nm;
      S[i].sym     = nm + InpSuffix;
      S[i].ready   = false;
      S[i].lastBar = 0;
      S[i].bwPct   = EMPTY_VALUE;
      S[i].adrPct  = EMPTY_VALUE;
      S[i].costPct = EMPTY_VALUE;
      S[i].tr.Reset();
      S[i].hBB = S[i].hEMA = S[i].hATRkc = S[i].hATR = INVALID_HANDLE;

      S[i].ok = SymbolSelect(S[i].sym, true);
      if(S[i].ok)
        {
         S[i].hBB    = iBands(S[i].sym, g_tf, InpBBPeriod, 0, InpBBDev, PRICE_CLOSE);
         S[i].hEMA   = iMA(S[i].sym, g_tf, InpKCPeriod, 0, MODE_EMA, PRICE_CLOSE);
         S[i].hATRkc = iATR(S[i].sym, g_tf, InpKCPeriod);
         S[i].hATR   = iATR(S[i].sym, g_tf, InpATRPeriod);
         S[i].ok = (S[i].hBB != INVALID_HANDLE && S[i].hEMA != INVALID_HANDLE &&
                    S[i].hATRkc != INVALID_HANDLE && S[i].hATR != INVALID_HANDLE);
        }
      if(!S[i].ok)
         PrintFormat("BBSqueezeDashboard: simbolo %s non disponibile", S[i].sym);
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "BBSqueezeDashboard");
   EventSetTimer(MathMax(1, InpTimerSec));
   Render();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < ArraySize(S); i++)
     {
      if(S[i].hBB    != INVALID_HANDLE) IndicatorRelease(S[i].hBB);
      if(S[i].hEMA   != INVALID_HANDLE) IndicatorRelease(S[i].hEMA);
      if(S[i].hATRkc != INVALID_HANDLE) IndicatorRelease(S[i].hATRkc);
      if(S[i].hATR   != INVALID_HANDLE) IndicatorRelease(S[i].hATR);
     }
   ObjectsDeleteAll(0, PFX);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
  {
   return rates_total;
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   for(int i = 0; i < ArraySize(S); i++)
      UpdateSymbol(i);
   Render();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      Render();
      return;
     }
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(StringFind(sparam, PFX + "r") != 0 || StringFind(sparam, "_c0") < 0)
      return;

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   int p1  = StringLen(PFX) + 1;
   int p2  = StringFind(sparam, "_c0");
   int row = (int)StringToInteger(StringSubstr(sparam, p1, p2 - p1));
   if(row < 1 || row > ArraySize(g_rowSym))
      return;
   int i = g_rowSym[row - 1];
   if(i < 0 || i >= ArraySize(S) || !S[i].ok)
      return;

   if(InpClick == CLICK_SWITCH)
      ChartSetSymbolPeriod(0, S[i].sym, g_tf);
   else
      ChartOpen(S[i].sym, g_tf);
  }

//+------------------------------------------------------------------+
//| Aggiorna un simbolo quando si chiude una sua barra                |
//+------------------------------------------------------------------+
void UpdateSymbol(const int i)
  {
   if(!S[i].ok)
      return;
   datetime t0 = iTime(S[i].sym, g_tf, 0);
   if(t0 == 0)
      return;
   if(S[i].ready && t0 == S[i].lastBar)
     {
      if(S[i].adrPct == EMPTY_VALUE)
         UpdateCosts(i, 0.0);   // dati D1 non ancora caricati al primo giro
      return;
     }

   int need = SqzBarsNeeded(P);
   int newBars;
   if(!S[i].ready)
      newBars = InpReplayBars;
   else
     {
      int sh = iBarShift(S[i].sym, g_tf, S[i].lastBar, true);
      if(sh < 1 || sh > InpReplayBars)
        {
         S[i].ready = false;      // buco nei dati: ricostruisco
         newBars = InpReplayBars;
        }
      else
         newBars = sh;
     }

   int avail = Bars(S[i].sym, g_tf);
   if(!S[i].ready)
      newBars = MathMin(newBars, avail - need - 2);
   if(newBars < 1)
      return;
   int bars = newBars + need + 1;

   if(BarsCalculated(S[i].hBB) < bars || BarsCalculated(S[i].hEMA) < bars ||
      BarsCalculated(S[i].hATRkc) < bars || BarsCalculated(S[i].hATR) < bars)
      return;

   double up[], mid[], lo[], ema[], akc[], atr[];
   MqlRates rt[];
   ArraySetAsSeries(up, true);  ArraySetAsSeries(mid, true); ArraySetAsSeries(lo, true);
   ArraySetAsSeries(ema, true); ArraySetAsSeries(akc, true); ArraySetAsSeries(atr, true);
   ArraySetAsSeries(rt, true);

   if(CopyBuffer(S[i].hBB, 1, 0, bars, up)     != bars) return;
   if(CopyBuffer(S[i].hBB, 0, 0, bars, mid)    != bars) return;
   if(CopyBuffer(S[i].hBB, 2, 0, bars, lo)     != bars) return;
   if(CopyBuffer(S[i].hEMA, 0, 0, bars, ema)   != bars) return;
   if(CopyBuffer(S[i].hATRkc, 0, 0, bars, akc) != bars) return;
   if(CopyBuffer(S[i].hATR, 0, 0, bars, atr)   != bars) return;
   if(CopyRates(S[i].sym, g_tf, 0, bars, rt)   != bars) return;

   bool live = S[i].ready;
   if(!live)
      S[i].tr.Reset();

   for(int s = newBars; s >= 1; s--)
     {
      SqzEvalResult r;
      SqzEvaluate(up, mid, lo, ema, akc, atr, s, true, P, r);
      int pre = S[i].tr.OnClosedBar(r, rt[s].high, rt[s].low, up[s], lo[s], rt[s].time, P);
      int brk = S[i].tr.OnBarOpen(rt[s - 1].open, up[s], lo[s], P);
      if(live && pre != 0)
         Notify(S[i].name, pre > 0 ? "PRE-ESPLOSIONE LONG" : "PRE-ESPLOSIONE SHORT");
      if(live && brk != 0)
         Notify(S[i].name, brk > 0 ? "BREAKOUT LONG" : "BREAKOUT SHORT");
      if(s == 1)
         S[i].bwPct = (r.bwMin > 0.0) ? (r.bw / r.bwMin - 1.0) * 100.0 : EMPTY_VALUE;
     }

//--- spread medio dalle barre analizzate
   double sprSum = 0.0;
   int    sprN   = 0;
   int    sprMax = MathMin(InpSpreadBars, bars);
   if(sprMax > bars - 1)
      sprMax = bars - 1;
   for(int s = 1; s <= sprMax; s++)
     {
      sprSum += rt[s].spread;
      sprN++;
     }
   UpdateCosts(i, sprN > 0 ? sprSum / sprN : 0.0);

   S[i].ready   = true;
   S[i].lastBar = t0;
  }

//+------------------------------------------------------------------+
//| ADR % e spread/ADR %                                              |
//| avgSpreadPts: spread medio in punti dalle barre (0 = non noto)    |
//+------------------------------------------------------------------+
void UpdateCosts(const int i, double avgSpreadPts)
  {
   MqlRates d[];
   int got = CopyRates(S[i].sym, PERIOD_D1, 1, InpAdrDays, d);   // solo giorni chiusi
   if(got < 5)
      return;
   double rng = 0.0, cls = 0.0;
   for(int k = 0; k < got; k++)
     {
      rng += d[k].high - d[k].low;
      cls += d[k].close;
     }
   rng /= got;
   cls /= got;
   if(rng <= 0.0 || cls <= 0.0)
      return;
   S[i].adrPct = rng / cls * 100.0;

   if(avgSpreadPts <= 0.0)
      avgSpreadPts = (double)SymbolInfoInteger(S[i].sym, SYMBOL_SPREAD);
   double point = SymbolInfoDouble(S[i].sym, SYMBOL_POINT);
   S[i].costPct = (point > 0.0 && avgSpreadPts > 0.0) ? avgSpreadPts * point / rng * 100.0 : EMPTY_VALUE;
  }

//+------------------------------------------------------------------+
//| Priorità: 5 breakout, 4 pre, 3 squeeze, 2 pronto/in formazione,   |
//| 1 vicino, 0 niente                                                |
//+------------------------------------------------------------------+
int Prio(const int i)
  {
   if(!S[i].ok || !S[i].ready)
      return 0;
   bool recent = (S[i].tr.lastEvent != 0 && S[i].tr.lastEventAge >= 0 && S[i].tr.lastEventAge <= InpEvMaxAge);
   if(recent && MathAbs(S[i].tr.lastEvent) == 3) return 5;
   if(recent)                                    return 4;
   if(S[i].tr.ValidSqueeze(P))                   return 3;
   if(S[i].tr.inSqz || S[i].tr.Armed(P))         return 2;
   if(InpShowNear && S[i].bwPct != EMPTY_VALUE && S[i].bwPct <= InpNearPct) return 1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Disegna la tabella                                                |
//+------------------------------------------------------------------+
void Render()
  {
   int n = ArraySize(S);
   int prio[];
   int idx[];
   ArrayResize(prio, n);
   ArrayResize(idx, n);
   for(int i = 0; i < n; i++)
     {
      prio[i] = Prio(i);
      idx[i]  = i;
     }

//--- ordinamento: priorità decrescente, poi costo crescente
   for(int a = 1; a < n; a++)
     {
      int key = idx[a];
      int b = a - 1;
      while(b >= 0 && Before(key, idx[b], prio))
        {
         idx[b + 1] = idx[b];
         b--;
        }
      idx[b + 1] = key;
     }

//--- righe da mostrare
   ArrayResize(g_rowSym, 0);
   for(int k = 0; k < n; k++)
     {
      int i = idx[k];
      if(InpOnlyActive && prio[i] == 0)
         continue;
      int r = ArraySize(g_rowSym);
      ArrayResize(g_rowSym, r + 1);
      g_rowSym[r] = i;
     }
   int rows = ArraySize(g_rowSym);

//--- geometria
   int rowH = InpFontSize * 2 + 6;
   int W = 0;
   for(int c = 0; c < NCOL; c++)
      W += COL_W[c];
   int bodyRows = MathMax(rows, 1);
   int H = (1 + bodyRows + (InpLegend ? 1 : 0)) * rowH;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int x0 = (InpPos == POS_TR || InpPos == POS_BR) ? cw - W - InpX : InpX;
   int y0 = (InpPos == POS_BL || InpPos == POS_BR) ? ch - H - InpY : InpY;

//--- intestazione
   int x = x0;
   for(int c = 0; c < NCOL; c++)
     {
      Cell("h_c" + IntegerToString(c), x, y0, COL_W[c], rowH, COL_TITLE[c], clrDimGray, clrWhite, false);
      x += COL_W[c];
     }

//--- corpo
   for(int r = 0; r < rows; r++)
     {
      int i  = g_rowSym[r];
      int y  = y0 + (r + 1) * rowH;
      string phase;
      color  bg;
      PhaseText(i, prio[i], phase, bg);

      string barsTxt = (S[i].ok && S[i].ready && S[i].tr.inSqz) ? IntegerToString(S[i].tr.sqCount) : "";
      string bwTxt   = (S[i].bwPct == EMPTY_VALUE)   ? "n/d" : "+" + DoubleToString(S[i].bwPct, 1) + "%";
      string adrTxt  = (S[i].adrPct == EMPTY_VALUE)  ? "n/d" : DoubleToString(S[i].adrPct, 2);
      string costTxt = (S[i].costPct == EMPTY_VALUE) ? "n/d" : DoubleToString(S[i].costPct, 1) + "%";
      color  costBg  = (S[i].costPct == EMPTY_VALUE) ? clrGray : S[i].costPct <= 5.0 ? clrSeaGreen : S[i].costPct <= 10.0 ? clrDarkGoldenrod : clrFireBrick;

      string rid = "r" + IntegerToString(r + 1) + "_c";
      x = x0;
      Cell(rid + "0", x, y, COL_W[0], rowH, S[i].name, clrRoyalBlue, clrWhite, true);  x += COL_W[0];
      Cell(rid + "1", x, y, COL_W[1], rowH, phase,     bg,           clrWhite, false); x += COL_W[1];
      Cell(rid + "2", x, y, COL_W[2], rowH, barsTxt,   clrGainsboro, clrBlack, false); x += COL_W[2];
      Cell(rid + "3", x, y, COL_W[3], rowH, bwTxt,     clrGainsboro, clrBlack, false); x += COL_W[3];
      Cell(rid + "4", x, y, COL_W[4], rowH, adrTxt,    clrGainsboro, clrBlack, false); x += COL_W[4];
      Cell(rid + "5", x, y, COL_W[5], rowH, costTxt,   costBg,       clrWhite, false);
     }

//--- riga vuota
   if(rows == 0)
     {
      string msg = (ArraySize(S) == 0) ? "Nessun simbolo" : AllReady() ? "Nessuno squeeze" : "Caricamento dati...";
      Cell("empty", x0, y0 + rowH, W, rowH, msg, clrGray, clrWhite, false);
     }
   else
      ObjectDelete(0, PFX + "empty");

//--- legenda
   if(InpLegend)
     {
      int yl = y0 + (1 + bodyRows) * rowH;
      Cell("legend", x0, yl, W, rowH,
           "BREAKOUT=conferma | PRE=banda+BW in salita | SQUEEZE=compressione | PRONTO=attendi PRE | (n)=barre fa",
           clrWhiteSmoke, clrDimGray, false);
     }
   else
      ObjectDelete(0, PFX + "legend");

//--- elimina le righe in eccesso
   for(int r = rows; r < g_prevRows; r++)
      for(int c = 0; c < NCOL; c++)
         ObjectDelete(0, PFX + "r" + IntegerToString(r + 1) + "_c" + IntegerToString(c));
   g_prevRows = rows;

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
bool Before(const int a, const int b, const int &prio[])
  {
   if(prio[a] != prio[b])
      return prio[a] > prio[b];
   double ca = (S[a].costPct == EMPTY_VALUE) ? 1e9 : S[a].costPct;
   double cb = (S[b].costPct == EMPTY_VALUE) ? 1e9 : S[b].costPct;
   return ca < cb;
  }

//+------------------------------------------------------------------+
bool AllReady()
  {
   for(int i = 0; i < ArraySize(S); i++)
      if(S[i].ok && !S[i].ready)
         return false;
   return true;
  }

//+------------------------------------------------------------------+
void PhaseText(const int i, const int pr, string &txt, color &bg)
  {
   if(!S[i].ok)    { txt = "n/d";         bg = clrGray; return; }
   if(!S[i].ready) { txt = "attesa dati"; bg = clrGray; return; }

   int  ev  = S[i].tr.lastEvent;
   int  age = S[i].tr.lastEventAge;
   string dir = (ev > 0) ? " " + ShortToString(0x25B2) : " " + ShortToString(0x25BC);
   string ago = (age > 0) ? " (" + IntegerToString(age) + ")" : "";

   switch(pr)
     {
      case 5: txt = "BREAKOUT" + dir + ago; bg = (ev > 0) ? clrGreen : clrRed;      break;
      case 4: txt = "PRE" + dir + ago;      bg = (ev > 0) ? clrTeal  : clrMaroon;   break;
      case 3: txt = "SQUEEZE";              bg = clrMediumBlue;                     break;
      case 2: txt = S[i].tr.inSqz ? "IN FORMAZIONE" : "PRONTO"; bg = clrDarkOrange; break;
      case 1: txt = "VICINO";               bg = clrSlateGray;                      break;
      default: txt = "-";                   bg = clrSilver;                         break;
     }
  }

//+------------------------------------------------------------------+
void Cell(const string id, const int x, const int y, const int w, const int h,
          const string text, const color bg, const color fg, const bool button)
  {
   string name = PFX + id;
   ENUM_OBJECT type = button ? OBJ_BUTTON : OBJ_EDIT;
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, type, 0, 0, 0))
         return;
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      if(!button)
        {
         ObjectSetInteger(0, name, OBJPROP_READONLY, true);
         ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
        }
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   if(button)
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
  }

//+------------------------------------------------------------------+
void Notify(const string sym, const string what)
  {
   string msg = sym + " " + StringSubstr(EnumToString(g_tf), 7) + ": " + what;
   if(InpAlerts) Alert(msg);
   if(InpPush)   SendNotification(msg);
  }
//+------------------------------------------------------------------+
