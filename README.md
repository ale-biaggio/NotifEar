# 👂 NotifEar – Riconoscimento Suoni per Apple Watch (+ companion iPhone)

**NotifEar** aiuta le persone **ipoudenti o sorde** a percepire i suoni ambientali. L'app **watchOS** usa il microfono dell'Apple Watch e il machine learning **on-device** per riconoscere suoni in tempo reale e avvisare con **vibrazioni aptiche**, **feedback visivo** e **notifiche locali**.

A questa si affianca una **app companion per iPhone** con cui l'utente può **insegnare suoni personalizzati** (es. il proprio citofono): si registrano dei campioni, si addestra un modello *direttamente sull'iPhone* e lo si invia al Watch, dove gira **accanto** al classificatore di sistema.

---

## 🧠 Come funziona

Sul Watch girano **due classificatori in parallelo** sullo stesso flusso del microfono (un solo tap audio, due richieste su `SNAudioStreamAnalyzer`):

```
                  ┌─────────────────────────────┐
   🎙️ microfono → │  SNAudioStreamAnalyzer       │
                  │   ├─ classificatore SISTEMA  │  ~300 suoni Apple (Version 1)
                  │   └─ classificatore CUSTOM   │  suoni addestrati dall'utente
                  └─────────────────────────────┘
                                │
                     vibrazione + alert + notifica
```

- Il **classificatore di sistema** (~300 suoni) è sempre attivo e non richiede addestramento.
- Il **classificatore personalizzato** è opzionale: esiste solo se l'utente ha addestrato e inviato un modello dall'iPhone.

---

## ⌚ App Watch — Funzionalità

### 🎙️ Riconoscimento audio in tempo reale
- Framework nativo Apple **SoundAnalysis** con il modello **Version 1** (~300 suoni) + l'eventuale **modello personalizzato**.
- Analisi interamente **on-device**, senza internet.
- Pipeline: `AVAudioSession` → `AVAudioEngine` → `SNAudioStreamAnalyzer`.

### 🌈 Categorie e scala di gravità
I suoni sono organizzati in **4 categorie** con un **codice colore proporzionale alla gravità** (verde → rosso) e una vibrazione dedicata. **La stessa scala vale sia per i suoni di sistema sia per quelli personalizzati**: a parità di categoria, sono indistinguibili al polso.

| Gravità | Colore | Categoria | Esempi (suoni di sistema) | Vibrazione |
|:---|:---|:---|:---|:---|
| **Emergenza** | 🔴 rosso | `emergency` | sirena ambulanza, sirena, allarme incendio, rilevatore di fumo | 3 vibrazioni rapide |
| **Suono urgente** | 🟠 arancione | `danger` | urlo, grido, clacson | 2 vibrazioni |
| **Suono domestico** | 🟡 giallo | `home` | campanello, bussare, telefono, suoneria | 1 tocco leggero |
| **Suono generico** | 🟢 verde | `attention` | pianto neonato, pianto, cane, abbaio | 1 vibrazione |

> Il nome interno della categoria (`emergency`/`danger`/`home`/`attention`) è la chiave usata per salvataggio e comunicazione col Watch e **non cambia**; i nomi leggibili e i colori sono definiti in un unico punto per app (`SoundCategory`).

### 🎯 Modalità Tracking (sonar aptico)
Toccando un suono rilevato si entra in **Tracking**: il Watch emette un pattern aptico continuo la cui **intensità è proporzionale a quanto il suono è forte/presente** in quel momento, per aiutare a localizzarne la sorgente. Quando il suono target sparisce, la vibrazione si zittisce (gating sulla confidence), anche se il rumore di fondo resta alto.

### ⏱️ Sessione estesa (~30 minuti)
- L'ascolto parte **automaticamente** all'apertura dell'app.
- `WKExtendedRuntimeSession` (tipo **Self Care**) mantiene il microfono attivo **anche a polso abbassato** o usando altre app.
- Timer di countdown con progress ring nella pagina dedicata.
- Alla scadenza: vibrazione di avviso e possibilità di riavviare.
- Se la sessione cade per errori esterni (es. debugger collegato), l'app prova a **riavviarla da sola**.

### 📲 Notifiche
- Se un suono viene rilevato mentre l'app è **in background**, arriva una **notifica locale** con il nome del suono.
- Se l'app è **in primo piano**, la notifica è soppressa (vedi già l'alert visivo).

### 🖐️ Gesture
- **Double Tap** (pizzico pollice-indice, Series 9+): chiude un alert attivo o riavvia la sessione se scaduta.
- **Tap sullo schermo**: chiude l'alert corrente.

### 🎨 Interfaccia
Navigazione a `TabView` (swipe orizzontale):
1. **Principale** — stato d'ascolto (icona `ear.and.waveform`), suono rilevato (tap → Tracking), sfondo a gradiente che cambia colore con la categoria, banner "nuovo suono ricevuto".
2. **Sessione** — timer circolare con minuti/secondi e stop/riavvia.
3. **Debug pattern** *(temporanea)* — griglia di test delle firme aptiche; da rimuovere prima del rilascio.

---

## 📱 App iPhone companion — Funzionalità

L'app companion (`NotifEar/`) serve a **insegnare suoni personalizzati** e a tenere lo **storico**. Due tab: **Suoni** e **Storico**.

### ➕ Crea e registra
- Crei un suono personalizzato (nome + categoria di gravità).
- Registri **più campioni** dello stesso suono (da distanze e volumi diversi: più varietà = riconoscimento migliore), li riascolti, ne elimini singoli.

### 🧪 Addestramento on-device
- Pulsante **"Addestra e invia al Watch"**: addestra un classificatore con **Create ML Components** (iOS 16+) **direttamente sull'iPhone** (nessun Mac), lo compila in `.mlmodelc` e lo spedisce al Watch.
- Servono **almeno 2 categorie/suoni**. Suggerimento: crea anche un suono **"rumore di fondo"** con campioni d'ambiente e tienilo **SPENTO** — serve come classe negativa per ridurre i falsi allarmi, ma non deve avvisare.

### 🔀 Sostituzione completa
Ogni "Addestra e invia" **sostituisce integralmente** il modello e le preferenze sul Watch (non si somma al precedente): i suoni eliminati spariscono davvero dal modello personalizzato.

### 🎚️ Interruttore "Avvisa"
Per ogni suono c'è un toggle: se spento, il Watch **riconosce comunque** quel suono ma **non avvisa**. Le modifiche all'interruttore arrivano al Watch **subito**, senza riaddestrare.

### 🗂️ Storico
I suoni rilevati dal Watch vengono inviati all'iPhone e raccolti nello **Storico**, raggruppati per sequenze consecutive, con colore della categoria e swipe-to-delete.

### 🛡️ Anti falsi positivi (suoni custom)
Il riconoscimento dei suoni personalizzati sul Watch è volutamente conservativo: confidenza alta sulla classe vincente, distacco netto dalla seconda, **conferma sostenuta** su più finestre consecutive e cooldown tra due avvisi — così un picco isolato non fa scattare l'allarme.

---

## 🔁 Flusso suoni personalizzati (end-to-end)

```
iPhone                                               Watch
──────                                               ─────
1. crei un suono + registri campioni
2. "Addestra e invia"
   → addestra (.mlmodelc) on-device
   → transferFile(modello + preferenze)  ───────►  riceve, ricostruisce e installa il modello
                                                     affianca la richiesta custom al sistema
3. sposti l'interruttore "Avvisa"
   → updateApplicationContext(preferenze) ───────►  aggiorna le preferenze al volo
                                          ◄───────  4. al rilevamento: transferUserInfo(evento)
   lo Storico raccoglie gli eventi
```

Comunicazione via **WatchConnectivity**: `transferFile` per il modello (consegna in background), `updateApplicationContext` per le preferenze (l'ultimo stato vince), `transferUserInfo` per gli eventi di rilevamento.

---

## 🏗️ Architettura

Pattern **MVVM**. Il progetto Xcode `NotifEar.xcodeproj` contiene **due target** (`NotifEar` iPhone, `NotifEar Watch App`) — è la struttura standard Apple per un'app Watch con companion iPhone.

### Watch App
| File | Ruolo |
|:---|:---|
| `NotifEarApp.swift` | Entry point. `TabView` con le 3 pagine. |
| `ContentView.swift` | Schermata principale: stato d'ascolto, suono rilevato (tap → Tracking), banner nuovo modello. |
| `SessionView.swift` | Timer circolare della sessione + stop/riavvia. |
| `SoundAnalyzerViewModel.swift` | Cuore: audio engine, classificatore di sistema + custom, categorie/colori/haptics, sessione estesa, notifiche, tracking. |
| `TrackingService.swift` · `TrackingView.swift` | Modalità Tracking (sonar aptico) di un suono target. |
| `CustomModelStore.swift` | Salva/installa il modello custom (`.mlmodelc`) e ne crea la richiesta di classificazione. |
| `CustomSoundConfigStore.swift` | Preferenze per-suono (avvisa sì/no + categoria) ricevute dall'iPhone. |
| `WatchModelReceiver.swift` | Lato Watch di WatchConnectivity: riceve modello + preferenze, invia gli eventi rilevati. |
| `ModelPackaging.swift` | Pacchettizza/ricostruisce la cartella `.mlmodelc` per il transfer. |
| `PatternDebugView.swift` | *(Temporanea)* griglia di test delle firme aptiche. |

### App iPhone companion
| File | Ruolo |
|:---|:---|
| `NotifEarPhoneApp.swift` | Entry point. `TabView` "Suoni" + "Storico". |
| `PhoneRootView.swift` | Elenco suoni, toggle "Avvisa", swipe-elimina, "Addestra e invia", stato connessione; include `AddSoundView` e l'enum `SoundCategory` (nomi/colori). |
| `RecordSampleView.swift` | Registrazione, riascolto ed eliminazione dei campioni di un suono. |
| `CustomSoundStore.swift` | Modello + persistenza dei suoni personalizzati e dei campioni. |
| `CustomSoundTrainer.swift` | Addestramento on-device (Create ML Components) e compilazione in `.mlmodelc`. |
| `PhoneConnectivityManager.swift` | Lato iPhone di WatchConnectivity: invia modello/preferenze, riceve gli eventi. |
| `DetectionHistoryStore.swift` · `HistoryView.swift` | Storico dei rilevamenti ricevuti dal Watch. |
| `SampleRecorder.swift` · `SamplePlayer.swift` | Registrazione e riproduzione audio dei campioni. |
| `ModelPackaging.swift` | Gemello del Watch: pacchettizzazione del modello. |

---

## ⚙️ Configurazione per sviluppatori

### Firma e Signing
Il `DEVELOPMENT_TEAM` nel progetto è vuoto. Ogni collaboratore imposta il proprio Team nel tab **Signing & Capabilities** di Xcode (per **entrambi** i target).

### Background Modes (Watch — obbligatorio su device fisico)
Target **NotifEar Watch App** → **Signing & Capabilities** → **+ Capability** → **Background Modes**:
1. ✅ **Audio**
2. ✅ **Extended Runtime Session** → **"Self Care"**

### Permessi microfono
Entrambe le app usano il microfono: assicurarsi che `NSMicrophoneUsageDescription` sia presente negli Info.plist di **iPhone** (registrazione campioni) e **Watch** (ascolto).

### Protezione file di progetto
Per non committare il proprio Team ID personale:
```bash
git update-index --assume-unchanged NotifEar.xcodeproj/project.pbxproj
```
> Se si aggiungono nuovi file al progetto, sbloccare con `--no-assume-unchanged`, committare con `git add -p` (escludendo la riga `DEVELOPMENT_TEAM`), poi ribloccare.

---

## 📋 Requisiti

- **Apple Watch**: watchOS **26.4+** (deployment target del progetto; Double Tap su Series 9 / Ultra 2 e successivi)
- **iPhone companion**: iOS **18.0+** (deployment target del progetto; l'addestramento on-device usa Create ML Components, introdotto in iOS 16)
- **iPhone e Watch abbinati** per inviare i suoni personalizzati
- **Xcode 26+** (SDK iOS 18 / watchOS 26)

---

## 📄 File di riferimento

| File | Descrizione |
|:---|:---|
| `SOUND_LABELS.md` | Catalogo curato dei suoni riconoscibili con traduzione italiana |
| `all_labels.txt` | Lista completa dei ~300 identifier del modello Apple |
