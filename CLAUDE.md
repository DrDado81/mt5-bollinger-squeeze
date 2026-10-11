# CLAUDE.md

Progetto MQL5 (MetaTrader 5): indicatore + EA Bollinger Squeeze. Lingua di lavoro: italiano (commenti e messaggi in italiano).

- La logica dello squeeze vive SOLO in `MQL5/Include/BBSqueeze/SqueezeCommon.mqh`; indicatore ed EA devono restare allineati. Ogni modifica alla definizione di squeeze va fatta lì.
- L'EA lavora solo su barre chiuse (una valutazione per nuova barra); non introdurre logica intrabar senza dirlo esplicitamente.
- Non si può compilare in questo ambiente: segnalare sempre che il codice va compilato in MetaEditor e verificato nello Strategy Tester.
- Nessun aumento silenzioso del rischio: se un vincolo del broker (lotto minimo, stops level) impedisce il trade, il trade si scarta con un messaggio nel log.
