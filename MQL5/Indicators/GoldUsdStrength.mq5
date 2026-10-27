//+------------------------------------------------------------------+
//|                                              GoldUsdStrength.mq5 |
//|  Micro-dashboard XAU / USD: un numero per Forza, Momentum e      |
//|  Volatilità, aggiornato in tempo reale (prezzo attuale incluso). |
//|                                                                  |
//|  Metodo (ricostruzione propria, non quella del vecchio           |
//|  indicatore con licenza, che non è nota):                        |
//|  - ogni valuta c del paniere è espressa in USD: lp_c = ±ln(prezzo|
//|    del cross con USD), lp_USD = 0, lp_XAU = ln(XAUUSD);          |
//|  - indice di c = lp_c − media(lp del paniere), cioè il valore    |
//|    di c contro la media del paniere (stile DXY equipesato);      |
//|  - Forza      = variazione dell'indice nelle ultime InpStrLen    |
//|                 barre fino al prezzo attuale, in unità di        |
//|                 volatilità normale (0 neutro, ±1 normale,        |
//|                 ±2 forte);                                       |
//|  - Momentum   = RSI(InpMomLen) dell'indice / 10 (0..10, 5 neutro)|
//|  - Volatilità = volatilità delle ultime InpVolShort barre (barra |
//|                 in formazione inclusa) / volatilità normale delle|
//|                 ultime InpVolLen barre chiuse (1.0 = normale).   |
//|  Descrive cosa sta succedendo adesso: non è una previsione.      |
//+------------------------------------------------------------------+
#property copyright   "Dario"
#property version     "1.00"
#property description "Forza / Momentum / Volatilità di XAU e USD in tempo reale"

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

enum ENUM_DASH_POS
  {
   POS_TL = 0, // In alto a sinistra
   POS_TR = 1, // In alto a destra
   POS_BL = 2, // In basso a sinistra
   POS_BR = 3  // In basso a destra
  };

//--- input
input group "Simboli"
input string          InpGold         = "XAUUSD";                     // Simbolo oro
input string          InpBasket       = "EUR,GBP,JPY,CHF,AUD,NZD,CAD"; // Valute del paniere (oltre a USD)
input string          InpSuffix       = "";                           // Suffisso broker (es. .r, m)
input bool            InpGoldInBasket = false;                        // Includi l'oro nella media del paniere

input group "Calcolo"
input ENUM_TIMEFRAMES InpTF           = PERIOD_M1;      // Timeframe di calcolo (indipendente dal grafico)
input int             InpStrLen       = 5;              // Forza: barre
input int             InpMomLen       = 14;             // Momentum: periodo RSI
input int             InpVolShort     = 5;              // Volatilità: barre recenti
input int             InpVolLen       = 60;             // Volatilità normale: barre chiuse
input double          InpNeutral      = 0.5;            // Forza: soglia neutra
input double          InpMomBand      = 1.0;            // Momentum: banda neutra attorno a 5
input double          InpVolHigh      = 1.5;            // Volatilità: soglia alta

input group "Pannello"
input ENUM_DASH_POS   InpPos          = POS_TR;         // Posizione
input int             InpX            = 10;             // Margine orizzontale (px)
input int             InpY            = 25;             // Margine verticale (px)
input int             InpFontSize     = 10;             // Dimensione testo
input int             InpRefreshMs    = 250;            // Aggiornamento (millisecondi)

//--- valuta del paniere espressa in USD
struct Leg
  {
   string            ccy;
   string            sym;
   int               sign;      // +1 se CCYUSD, -1 se USDCCY
   double            lp[];      // ±ln(prezzo) allineato ai tempi dell'oro
  };

Leg             L[];            // L[0] = oro, poi il paniere FX
ENUM_TIMEFRAMES g_tf;
int             g_need = 0;     // barre necessarie
uint            g_lastMs = 0;
string          g_status = "";
bool            g_ready = false;

//--- risultati: [0] = XAU, [1] = USD
double g_str[2], g_mom[2], g_vol[2];

const string PFX = "GUS_";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpStrLen < 1 || InpMomLen < 2 || InpVolShort < 1 || InpVolLen < 3)
     {
      Print("GoldUsdStrength: parametri non validi");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_tf   = (InpTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpTF;
   g_need = MathMax(MathMax(InpStrLen, InpVolShort), MathMax(3 * InpMomLen, InpVolLen + 1)) + 2;

   ArrayResize(L, 1);
   L[0].ccy  = "XAU";
   L[0].sym  = InpGold + InpSuffix;
   L[0].sign = 1;
   if(!SymbolSelect(L[0].sym, true))
     {
      PrintFormat("GoldUsdStrength: simbolo oro %s non disponibile", L[0].sym);
      return INIT_FAILED;
     }

   string parts[];
   int n = StringSplit(InpBasket, ',', parts);
   for(int k = 0; k < n; k++)
     {
      string c = parts[k];
      StringTrimLeft(c);
      StringTrimRight(c);
      StringToUpper(c);
      if(c == "" || c == "USD")
         continue;
      string s1 = c + "USD" + InpSuffix;
      string s2 = "USD" + c + InpSuffix;
      int sign = 0;
      string sym = "";
      if(SymbolSelect(s1, true))      { sym = s1; sign =  1; }
      else if(SymbolSelect(s2, true)) { sym = s2; sign = -1; }
      if(sign == 0)
        {
         PrintFormat("GoldUsdStrength: né %s né %s disponibili, %s escluso dal paniere", s1, s2, c);
         continue;
        }
      int i = ArraySize(L);
      ArrayResize(L, i + 1);
      L[i].ccy  = c;
      L[i].sym  = sym;
      L[i].sign = sign;
     }
   if(ArraySize(L) < 2)
      Print("GoldUsdStrength: paniere vuoto, la forza è calcolata solo su XAU e USD");

   IndicatorSetString(INDICATOR_SHORTNAME, "GoldUsdStrength");
   EventSetMillisecondTimer(MathMax(50, InpRefreshMs));
   Refresh(true);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
  {
   Refresh(false);
   return rates_total;
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   Refresh(true);
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      Render();
  }

//+------------------------------------------------------------------+
//| Ricalcola e ridisegna; dai tick del grafico al massimo ogni 100ms|
//+------------------------------------------------------------------+
void Refresh(const bool force)
  {
   uint now = GetTickCount();
   if(!force && now - g_lastMs < 100)
      return;
   g_lastMs = now;
   g_ready  = Compute();
   Render();
  }

//+------------------------------------------------------------------+
bool Compute()
  {
   datetime rt[];
   if(CopyTime(L[0].sym, g_tf, 0, g_need, rt) != g_need)
     {
      g_status = "dati " + L[0].ccy;
      return false;
     }
   for(int i = 0; i < ArraySize(L); i++)
      if(!FillLeg(i, rt))
        {
         g_status = "dati " + L[i].ccy;
         return false;
        }

//--- indici XAU e USD contro la media del paniere
   double ix[], iu[];
   ArrayResize(ix, g_need);
   ArrayResize(iu, g_need);
   int nFx = ArraySize(L) - 1;
   int cnt = 1 + nFx + (InpGoldInBasket ? 1 : 0);   // 1 = USD (lp = 0)
   for(int k = 0; k < g_need; k++)
     {
      double sum = InpGoldInBasket ? L[0].lp[k] : 0.0;
      for(int i = 1; i <= nFx; i++)
         sum += L[i].lp[k];
      double mean = sum / cnt;
      ix[k] = L[0].lp[k] - mean;
      iu[k] = -mean;
     }

   if(!Stats(ix, 0) || !Stats(iu, 1))
     {
      g_status = "dati piatti";
      return false;
     }
   g_status = "";
   return true;
  }

//+------------------------------------------------------------------+
//| Forza, momentum e volatilità di un indice                        |
//+------------------------------------------------------------------+
bool Stats(const double &x[], const int j)
  {
   int    last = g_need - 1;
   double norm = Rms(x, last - InpVolLen, last - 1);       // solo barre chiuse
   if(norm <= 0.0)
      return false;
   g_str[j] = (x[last] - x[last - InpStrLen]) / (norm * MathSqrt((double)InpStrLen));
   g_mom[j] = Rsi(x) / 10.0;
   g_vol[j] = Rms(x, last - InpVolShort + 1, last) / norm; // barra in formazione inclusa
   return true;
  }

//+------------------------------------------------------------------+
//| Variazione quadratica media per barra, da x[from] a x[to]        |
//+------------------------------------------------------------------+
double Rms(const double &x[], const int from, const int to)
  {
   double sq = 0.0;
   for(int k = from; k <= to; k++)
     {
      double d = x[k] - x[k - 1];
      sq += d * d;
     }
   return MathSqrt(sq / (to - from + 1));
  }

//+------------------------------------------------------------------+
//| Chiusure del simbolo allineate ai tempi dell'oro (ultimo valore  |
//| noto a quell'ora). La barra in formazione usa il prezzo attuale. |
//+------------------------------------------------------------------+
bool FillLeg(const int i, const datetime &rt[])
  {
   ArrayResize(L[i].lp, g_need);
   if(i == 0)
     {
      double c[];
      if(CopyClose(L[0].sym, g_tf, 0, g_need, c) != g_need)
         return false;
      for(int k = 0; k < g_need; k++)
        {
         if(c[k] <= 0.0)
            return false;
         L[0].lp[k] = MathLog(c[k]);
        }
      return true;
     }

//--- l'oro ha meno ore di contrattazione delle valute: serve più storia
   int want = g_need * 2;
   datetime t[];
   double   c[];
   int m = 0;
   for(int attempt = 0; attempt < 3; attempt++, want *= 2)
     {
      m = CopyTime(L[i].sym, g_tf, 0, want, t);
      if(m <= 0 || CopyClose(L[i].sym, g_tf, 0, m, c) != m)
         return false;
      if(t[0] <= rt[0] || m < want)
         break;
     }
   if(t[0] > rt[0])
      return false;

   int j = 0;
   for(int k = 0; k < g_need; k++)
     {
      while(j + 1 < m && t[j + 1] <= rt[k])
         j++;
      if(c[j] <= 0.0)
         return false;
      L[i].lp[k] = L[i].sign * MathLog(c[j]);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| RSI di Wilder sull'intera serie (riscaldamento ≥ 2 periodi)      |
//+------------------------------------------------------------------+
double Rsi(const double &x[])
  {
   int n = ArraySize(x);
   double ag = 0.0, al = 0.0;
   for(int k = 1; k <= InpMomLen; k++)
     {
      double d = x[k] - x[k - 1];
      if(d > 0) ag += d; else al -= d;
     }
   ag /= InpMomLen;
   al /= InpMomLen;
   for(int k = InpMomLen + 1; k < n; k++)
     {
      double d = x[k] - x[k - 1];
      ag = (ag * (InpMomLen - 1) + (d > 0 ?  d : 0.0)) / InpMomLen;
      al = (al * (InpMomLen - 1) + (d < 0 ? -d : 0.0)) / InpMomLen;
     }
   if(ag + al <= 0.0)
      return 50.0;
   return 100.0 * ag / (ag + al);
  }

//+------------------------------------------------------------------+
color StrColor(const double v)
  {
   if(v >  InpNeutral) return clrLime;
   if(v < -InpNeutral) return clrRed;
   return clrSilver;
  }

//+------------------------------------------------------------------+
color MomColor(const double v)
  {
   if(v > 5.0 + InpMomBand) return clrLime;
   if(v < 5.0 - InpMomBand) return clrRed;
   return clrSilver;
  }

//+------------------------------------------------------------------+
color VolColor(const double v)
  {
   return (v >= InpVolHigh) ? clrOrange : clrWhite;
  }

//+------------------------------------------------------------------+
void Render()
  {
   int fs   = InpFontSize;
   int rowH = fs * 2 + 2;
   int pad  = fs;
   int c0   = fs * 8;          // colonna etichette
   int cw   = fs * 5;          // colonne XAU / USD
   int W    = pad * 2 + c0 + cw * 2;
   int H    = pad + rowH * 4;
   int chW  = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chH  = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int x0   = (InpPos == POS_TR || InpPos == POS_BR) ? chW - W - InpX : InpX;
   int y0   = (InpPos == POS_BL || InpPos == POS_BR) ? chH - H - InpY : InpY;
   int xl   = x0 + pad;
   int xr[2];                  // bordo destro delle colonne XAU / USD
   xr[0] = xl + c0 + cw;
   xr[1] = xr[0] + cw;

   Box(x0, y0, W, H);

//--- intestazione: timeframe, o lo stato finché i dati non sono pronti
   int y = y0 + pad / 2;
   Txt("stat", xl, y, g_ready ? StringSubstr(EnumToString(g_tf), 7) : g_status,
       g_ready ? clrGray : clrOrange, false, false);
   Txt("hx", xr[0], y, "XAU", clrGold,       true, true);
   Txt("hu", xr[1], y, "USD", clrDodgerBlue, true, true);

   string row[3] = {"Forza", "Momentum", "Volatilità"};
   for(int r = 0; r < 3; r++)
     {
      y += rowH;
      Txt("l" + IntegerToString(r), xl, y, row[r], clrGray, false, false);
      for(int j = 0; j < 2; j++)
        {
         string txt = "-";
         color  clr = clrGray;
         if(g_ready)
            switch(r)
              {
               case 0:  txt = StringFormat("%+.1f", g_str[j]); clr = StrColor(g_str[j]); break;
               case 1:  txt = DoubleToString(g_mom[j], 1);     clr = MomColor(g_mom[j]); break;
               default: txt = DoubleToString(g_vol[j], 1);     clr = VolColor(g_vol[j]); break;
              }
         Txt("v" + IntegerToString(r) + IntegerToString(j), xr[j], y, txt, clr, true, j == 0);
        }
     }

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
void Box(const int x, const int y, const int w, const int h)
  {
   string name = PFX + "bg";
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'20,24,32');
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_COLOR, C'60,66,80');
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
  }

//+------------------------------------------------------------------+
void Txt(const string id, const int x, const int y, const string text,
         const color clr, const bool alignRight, const bool bold)
  {
   string name = PFX + id;
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, alignRight ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }
//+------------------------------------------------------------------+
