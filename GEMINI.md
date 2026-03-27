# Contesto del Progetto: NotifEar – App watchOS per Riconoscimento Audio

Questo progetto è un'applicazione **standalone per watchOS**, sviluppata interamente in **Swift** e **SwiftUI**. L'obiettivo è riconoscere suoni ambientali in tempo reale sfruttando l'hardware dell'Apple Watch e notificare l'utente tramite feedback aptico.

## Architettura

L'app segue il pattern **MVVM** (Model-View-ViewModel):

| File | Ruolo |
| :--- | :--- |
| `NotifEarApp.swift` | Entry point (`@main`). Crea il ViewModel condiviso e la `TabView` con navigazione a pagine. |
| `ContentView.swift` | **View principale** – Mostra l'animazione di ascolto, l'icona del suono rilevato e lo sfondo dinamico a gradiente. |
| `SessionView.swift` | **View sessione** – Timer circolare con tempo rimanente, pulsante stop/riavvia. Raggiungibile con swipe orizzontale. |
| `SoundAnalyzerViewModel.swift` | **ViewModel** – Tutta la logica: permessi microfono, audio engine, analisi ML, gestione sessione estesa e timer. |

### Navigazione
- `TabView` con `.tabViewStyle(.page)` per swipe orizzontale tra le due pagine.
- Pagina 1 (default): ascolto e feedback visivo.
- Pagina 2 (swipe sinistra): timer sessione e controlli.

### Regole Architetturali
- Separazione rigorosa tra View e logica di business (ViewModel/ObservableObject).
- Nessuna logica complessa, richiesta permessi o gestione sensori dentro le View.

## Modello di Riconoscimento Audio

L'app utilizza **esclusivamente** il framework nativo Apple **`SoundAnalysis`**, in particolare:

- **`SNClassifySoundRequest(classifierIdentifier: .version1)`** – Il classificatore predefinito di Apple (Version 1), un modello ML on-device capace di riconoscere **~300 suoni** diversi (lista completa in `all_labels.txt`).
- **Non vengono usati** modelli esterni, Core ML personalizzati, o framework di terze parti.

### Pipeline Audio
1. `AVAudioSession` configurata in modalità `.record` / `.measurement`.
2. `AVAudioEngine` cattura audio dal microfono con un tap sul `inputNode` (buffer 8192 frame).
3. `SNAudioStreamAnalyzer` analizza ogni buffer in un thread dedicato (`AnalysisQueue`).
4. I risultati vengono filtrati: soglia di debug a **40%** (log in console), soglia di notifica a **55%** (alert utente).

## Gestione Sessione

L'app usa `WKExtendedRuntimeSession` per mantenere l'ascolto attivo anche a schermo spento (polso abbassato):

- **Durata**: ~30 minuti per sessione.
- **Avvio automatico**: l'ascolto parte all'apertura dell'app senza interazione.
- **Timer**: countdown visibile nella pagina sessione con progress ring circolare.
- **Scadenza**: alla fine della sessione, l'ascolto si ferma, un feedback aptico avvisa l'utente, e viene mostrato il pulsante "Riavvia".
- **Chiusura**: l'utente può fermare l'ascolto dal pulsante stop o chiudere l'app dalle recenti.

## Suoni Monitorati

Dei ~300 suoni riconoscibili dal modello, l'app ne filtra **un sottoinsieme specifico**, organizzato in 4 categorie con colori e feedback aptici diversi:

| Categoria | Suoni (identifier) | Colore | Haptic |
| :--- | :--- | :--- | :--- |
| 🚨 **Emergency** | `ambulance_siren`, `siren`, `fire_alarm`, `smoke_detector` | Rosso | 3× `.directionUp` |
| ⚠️ **Danger** | `scream`, `shout`, `car_horn` | Arancione | 2× `.notification` |
| 🏠 **Home** | `door_bell`/`doorbell`, `knock`, `telephone_bell`, `ringtone` | Blu/Verde | 1× `.click` |
| 👶 **Attention** | `baby_crying`/`baby_cry`, `crying`, `dog`, `bark` | Giallo/Arancione | 1× `.retry` |

Ogni suono ha un'icona **SF Symbols** associata e un'etichetta in italiano mostrata all'utente.

### Alert Visivo
Quando un suono viene rilevato:
- Lo sfondo cambia con un gradiente del colore della categoria.
- L'icona SF Symbol del suono appare al centro.
- Il feedback aptico viene attivato (pattern ripetuto per emergenze/pericoli).
- Dopo **5 secondi** senza un nuovo rilevamento dello stesso tipo, l'UI torna allo stato "In ascolto...".

### Interazione e Gesture
- **Double Tap** (pizzico pollice-indice, Series 9+): dismissare un alert attivo, oppure riavviare la sessione se scaduta.
- **Tap sullo schermo**: dismissare l'alert del suono corrente.
- Implementato tramite `.handGestureShortcut(.primaryAction)` su un `Button` nascosto.

## Direttive Tecnologiche
- Per il riconoscimento audio, si usa esclusivamente il framework nativo `SoundAnalysis` con classificazioni predefinite (`SNClassifySoundRequest`).
- Al momento non devono essere integrati modelli esterni, framework di terze parti o esportazioni da Teachable Machine.
- La gestione dei permessi hardware (microfono tramite `AVAudioSession`) è isolata nel ViewModel.

## File Ausiliari
- **`SOUND_LABELS.md`** – Catalogo curato dei suoni più rilevanti, con traduzione italiana, raggruppati per categoria.
- **`all_labels.txt`** – Lista completa dei ~300 identifier riconosciuti dal modello Apple Version 1.
- **`check_labels.swift`** / **`get_all_labels.swift`** – Script di utilità per esplorare le etichette del modello.
