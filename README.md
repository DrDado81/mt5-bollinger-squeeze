# MT5 Bollinger Squeeze

Indicatore + Expert Advisor MQL5 per identificare gli squeeze delle Bande di Bollinger e operare il breakout.

## File

| File | Destinazione in MT5 (`File > Apri cartella dati`) |
|---|---|
| `MQL5/Include/BBSqueeze/SqueezeCommon.mqh` | `MQL5\Include\BBSqueeze\` |
| `MQL5/Indicators/BBSqueeze.mq5` | `MQL5\Indicators\` |
| `MQL5/Experts/BBSqueezeEA.mq5` | `MQL5\Experts\` |

Compilare in MetaEditor (F7) prima l'indicatore, poi l'EA. L'EA **non** dipende dall'indicatore (calcola tutto internamente con la stessa logica dell'include comune), quindi indicatore ed EA danno sempre lo stesso squeeze a parità di parametri.

## Definizione di squeeze

- `SQZ_BANDWIDTH` (default): BandWidth = (Upper − Lower) / Middle × 100. Squeeze se il BandWidth è entro `InpBWTolPct`% dal minimo delle ultime `InpBWLookback` barre. Il default 125 riprende la regola di Bollinger (BandWidth ai minimi di ~6 mesi su grafico daily); su timeframe intraday va ricalibrato.
- `SQZ_KELTNER`: bande di Bollinger interamente dentro il canale di Keltner (EMA ± ATR × 1.5), stile TTM Squeeze.
- `SQZ_BOTH`: entrambe.

Indicatore: istogramma grigio = no squeeze, rosso = squeeze, verde = prima barra di rilascio; linea tratteggiata = soglia. Buffer 3 = stato squeeze (1/0) leggibile via `iCustom`.

## Logica EA

1. Episodio di squeeze valido se dura almeno `InpMinSqueezeBars`; si registrano max/min delle barre di squeeze.
2. Setup armato durante lo squeeze valido e per `InpArmedBars` barre dopo la fine.
3. Ingresso:
   - `ENTRY_CLOSE_BREAKOUT`: chiusura oltre la banda (e, se `InpRequireRangeBreak`, oltre max/min dello squeeze) → ordine a mercato all'apertura della barra successiva.
   - `ENTRY_PENDING_OCO`: buy stop sul massimo e sell stop sul minimo dello squeeze; quando uno scatta l'altro viene cancellato.
4. SL oltre il lato opposto del range (+ `InpSLBufferATR` × ATR). Trade scartato se SL > `InpMaxSL_ATR` × ATR.
5. TP: multiplo dell'altezza del range, R:R, o nessuno. Trailing opzionale su banda centrale o ATR.
6. Un solo trade per episodio. Lotto fisso o % di rischio sul balance (se il lotto calcolato è sotto il minimo del broker il trade viene scartato, non arrotondato per eccesso).
7. All'avvio l'EA ricostruisce lo stato dalle ultime `InpReplayBars` barre senza aprire trade.

## Da verificare in MT5

Il codice è stato scritto fuori da MetaEditor e non è ancora stato compilato né testato. Prima dell'uso reale:

1. Compilazione senza errori/warning.
2. Confronto visivo: rettangoli dell'EA (`InpDrawRange`) vs barre rosse dell'indicatore.
3. Strategy Tester "Ogni tick basato su tick reali", su più simboli/timeframe, con costi reali.

## TradingView: `tradingview/BB_Squeeze_PreBreakout.pine`

Indicatore Pine Script v6 a tre fasi:

1. **Squeeze** (sfondo rosso nel pannello BW): BW entro `tolPct`% dalla linea "Lowest Contraction" (minimo di 125 barre, come il BBW integrato di TradingView e l'EA MT5), BW piatto e media centrale piatta (entrambi disattivabili).
2. **Pre-esplosione** (triangolo "Pre" sul prezzo): durante uno squeeze valido o entro `armBars` barre dalla fine, candela chiusa sulla banda superiore/inferiore e BW in salita da `riseBars` barre. Una volta per direzione per episodio.
3. **Conferma** (etichetta "OK"): entro `confBars` barre, una candela apre oltre la banda della barra precedente.

Installazione: Pine Editor → incolla → Salva → Aggiungi al grafico. Alert: crea un alert scegliendo l'indicatore e la condizione. Per il Pine Screener usare il plot "Stato" (3/-3 conferma, 2/-2 pre-esplosione, 1 squeeze).
