//+------------------------------------------------------------------+
//|                                              GoldUsdStrength.mq5 |
//|  Micro-dashboard: forza, momentum e volatilità di XAU e USD      |
//|  rispetto a un paniere di valute, aggiornata in tempo reale      |
//|  (barra in formazione inclusa).                                  |
//|                                                                  |
//|  Metodo (ricostruzione propria, non quella del vecchio           |
//|  indicatore con licenza, che non è nota):                        |
//|  - ogni valuta c del paniere è espressa in USD: lp_c = ±ln(prezzo|
//|    del cross con USD), lp_USD = 0, lp_XAU = ln(XAUUSD);          |
//|  - indice di c = lp_c − media(lp del paniere), cioè il valore    |
//|    di c contro la media del paniere (stile DXY equipesato);      |
//|  - Forza      = variazione % dell'indice in InpStrLen barre;     |
//|  - Momentum   = RSI(InpMomLen) dell'indice / 10 (0..10, 5 neutro)|
//|  - Volatilità = variazione % media assoluta per barra            |
//|                 dell'indice (InpVolLen barre);                   |
//|  - Corr       = correlazione di Pearson delle variazioni per     |
//|                 barra degli indici XAU e USD (InpCorrLen barre). |
//|  Forza XAU − Forza USD = variazione % di XAUUSD (identità).      |
//+------------------------------------------------------------------+
#property copyright   "Dario"
#property version     "1.00"
#property description "Forza / momentum / volatilità di XAU e USD vs paniere valute"

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
input ENUM_TIMEFRAMES InpTF           = PERIOD_CURRENT; // Timeframe
input int             InpStrLen       = 20;             // Forza: barre di variazione
input int             InpMomLen       = 14;             // Momentum: periodo RSI
input int             InpVolLen       = 20;             // Volatilità: barre
input int             InpCorrLen      = 50;             // Correlazione: barre
input double          InpNeutral      = 0.10;           // Forza: soglia neutra (%)
input double          InpMomBand      = 1.0;            // Momentum: banda neutra attorno a 5

input group "Pannello"
input ENUM_DASH_POS   InpPos          = POS_TR;         // Posizione
input int             InpX            = 10;             // Margine orizzontale (px)
input int             InpY            = 25;             // Margine verticale (px)
input int             InpFontSize     = 9;              // Dimensione testo
input int             InpRefreshMs    = 250;            // Aggiornamento (millisecondi)

//--- valuta del paniere espressa in USD
struct Leg
  {
   string            ccy;
   string            sym;
   int               sign;      // +1 se CCYUSD, -1 se USDCCY
   bool              ok;
   double            lp[];      // ±ln(prezzo) allineato ai tempi dell'oro
  };

Leg             L[];            // L[0] = oro, poi il paniere FX
ENUM_TIMEFRAMES g_tf;
int             g_need = 0;     // barre necessarie
uint            g_lastMs = 0;
string          g_status = "";
bool            g_ready = false;

//--- risultati
double g_strX, g_strU, g_momX, g_momU, g_volX, g_volU, g_corr;

const string PFX = "GUS_";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpStrLen < 1 || InpMomLen < 2 || InpVolLen < 1 || InpCorrLen < 3)
     {
      Print("GoldUsdStrength: parametri non validi");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_tf   = (InpTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpTF;
   g_need = MathMax(MathMax(InpStrLen, 3 * InpMomLen), MathMax(InpVolLen, InpCorrLen)) + 2;

   ArrayResize(L, 1);
   L[0].ccy  = "XAU";
   L[0].sym  = InpGold + InpSuffix;
   L[0].sign = 1;
   L[0].ok   = SymbolSelect(L[0].sym, true);
   if(!L[0].ok)
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
      int i = ArraySize(L);
      ArrayResize(L, i + 1);
      L[i].ccy = c;
      L[i].ok  = false;
      string s1 = c + "USD" + InpSuffix;
      string s2 = "USD" + c + InpSuffix;
      if(SymbolSelect(s1, true))      { L[i].sym = s1; L[i].sign =  1; L[i].ok = true; }
      else if(SymbolSelect(s2, true)) { L[i].sym = s2; L[i].sign = -1; L[i].ok = true; }
      if(!L[i].ok)
        {
         PrintFormat("GoldUsdStrength: né %s né %s disponibili, %s escluso dal paniere", s1, s2, c);
         ArrayResize(L, i);
        }
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
      g_status = "attesa dati " + L[0].ccy;
      return false;
     }
   for(int i = 0; i < ArraySize(L); i++)
      if(!FillLeg(i, rt))
        {
         g_status = "attesa dati " + L[i].ccy;
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

   int last = g_need - 1;
   g_strX = (ix[last] - ix[last - InpStrLen]) * 100.0;
   g_strU = (iu[last] - iu[last - InpStrLen]) * 100.0;
   g_momX = Rsi(ix) / 10.0;
   g_momU = Rsi(iu) / 10.0;
   g_volX = MeanAbsDiff(ix, InpVolLen) * 100.0;
   g_volU = MeanAbsDiff(iu, InpVolLen) * 100.0;
   g_corr = CorrDiff(ix, iu, InpCorrLen);
   g_status = "";
   return true;
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
double MeanAbsDiff(const double &x[], const int len)
  {
   int n = ArraySize(x);
   double s = 0.0;
   for(int k = n - len; k < n; k++)
      s += MathAbs(x[k] - x[k - 1]);
   return s / len;
  }

//+------------------------------------------------------------------+
double CorrDiff(const double &a[], const double &b[], const int len)
  {
   int n = ArraySize(a);
   double sa = 0, sb = 0, saa = 0, sbb = 0, sab = 0;
   for(int k = n - len; k < n; k++)
     {
      double da = a[k] - a[k - 1];
      double db = b[k] - b[k - 1];
      sa += da; sb += db; saa += da * da; sbb += db * db; sab += da * db;
     }
   double cov = sab - sa * sb / len;
   double va  = saa - sa * sa / len;
   double vb  = sbb - sb * sb / len;
   if(va <= 0.0 || vb <= 0.0)
      return 0.0;
   return cov / MathSqrt(va * vb);
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
void Render()
  {
   int fs   = InpFontSize;
   int rowH = fs * 2 + 2;
   int pad  = fs;
   int c0   = fs * 5;          // colonna etichette
   int cw   = fs * 7;          // colonne numeriche
   int W    = pad * 2 + c0 + cw * 3;
   int H    = pad + rowH * 6;
   int chW  = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chH  = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int x0   = (InpPos == POS_TR || InpPos == POS_BR) ? chW - W - InpX : InpX;
   int y0   = (InpPos == POS_BL || InpPos == POS_BR) ? chH - H - InpY : InpY;
   int xl   = x0 + pad;
   int xr1  = xl + c0 + cw;    // bordo destro delle colonne numeriche
   int xr2  = xr1 + cw;
   int xr3  = xr2 + cw;

   Box(x0, y0, W, H);

   string tf = StringSubstr(EnumToString(g_tf), 7);
   int y = y0 + pad / 2;
   Txt("title", xl, y, "XAU vs USD  " + tf, clrWhite, false, true);
   Txt("stat",  xr3, y, g_ready ? "LIVE" : g_status, g_ready ? clrLime : clrOrange, true, false);

   y += rowH;
   Txt("h1", xr1, y, "Forza%", clrGray, true, false);
   Txt("h2", xr2, y, "Mom",    clrGray, true, false);
   Txt("h3", xr3, y, "Vol%",   clrGray, true, false);

   string nd = "-";
   y += rowH;
   Txt("xl", xl,  y, "XAU", clrGold, false, true);
   Txt("xs", xr1, y, g_ready ? StringFormat("%+.2f", g_strX) : nd, g_ready ? StrColor(g_strX) : clrGray, true, false);
   Txt("xm", xr2, y, g_ready ? DoubleToString(g_momX, 1)   : nd, g_ready ? MomColor(g_momX) : clrGray, true, false);
   Txt("xv", xr3, y, g_ready ? DoubleToString(g_volX, 3)   : nd, clrWhite, true, false);

   y += rowH;
   Txt("ul", xl,  y, "USD", clrDodgerBlue, false, true);
   Txt("us", xr1, y, g_ready ? StringFormat("%+.2f", g_strU) : nd, g_ready ? StrColor(g_strU) : clrGray, true, false);
   Txt("um", xr2, y, g_ready ? DoubleToString(g_momU, 1)   : nd, g_ready ? MomColor(g_momU) : clrGray, true, false);
   Txt("uv", xr3, y, g_ready ? DoubleToString(g_volU, 3)   : nd, clrWhite, true, false);

   double diff = g_strX - g_strU;
   y += rowH;
   Txt("dl", xl,  y, "X-U", clrGray, false, false);
   Txt("ds", xr1, y, g_ready ? StringFormat("%+.2f", diff) : nd, g_ready ? StrColor(diff) : clrGray, true, false);
   Txt("cl", xr2, y, "Corr", clrGray, true, false);
   Txt("cv", xr3, y, g_ready ? StringFormat("%+.2f", g_corr) : nd, clrWhite, true, false);

//--- lettura sintetica
   string bias = "-";
   color  bc   = clrGray;
   if(g_ready)
     {
      double n = InpNeutral;
      if(g_strX > n && g_strU < -n)      { bias = "XAU forte / USD debole"; bc = clrLime; }
      else if(g_strX < -n && g_strU > n) { bias = "XAU debole / USD forte"; bc = clrRed; }
      else if(diff > n)                  { bias = "XAU > USD";              bc = clrPaleGreen; }
      else if(diff < -n)                 { bias = "XAU < USD";              bc = clrLightSalmon; }
      else                               { bias = "neutro";                 bc = clrSilver; }
     }
   y += rowH;
   Txt("bias", xl, y, bias, bc, false, true);

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
