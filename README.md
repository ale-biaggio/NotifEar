# 👂 NotifEar – Riconoscimento Suoni per Apple Watch (+ companion iPhone)

**NotifEar** aiuta le persone **ipoudenti o sorde** a percepire i suoni ambientali. L'app **watchOS** usa il microfono dell'Apple Watch e il machine learning **on-device** per riconoscere suoni in tempo reale e avvisare con **vibrazioni aptiche**, **feedback visivo** e **notifiche locali**.

A questa si affianca una **app companion per iPhone** con due ruoli:
1. **Insegnare suoni personalizzati** (es. il proprio citofono): si registrano campioni, si addestra un modello *direttamente sull'iPhone* e lo si invia al Watch, dove gira **accanto** al classificatore di sistema.
2. **Modalità Sonar** (novità): localizzare un suono già riconosciuto facendo vibrare l'iPhone in modo **granulare** (intensità *e* frequenza proporzionali al volume), attivata con un tocco dall'Apple Watch. Sfrutta il Taptic Engine dell'iPhone, che — a differenza del Watch — permette vibrazioni a intensità continua.

---

## 🧠 Come funziona il riconoscimento

Sul Watch (e, in modalità Sonar, anche sull'iPhone) girano **due classificatori in parallelo** sullo stesso flusso del microfono (un solo tap audio, due richieste su `SNAudioStreamAnalyzer`):

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
- Il **classificatore personalizzato** è opzionale: esiste solo se l'utente ha addestrato e inviato un modello dall'iPhone. Lo **stesso** `.mlmodelc` viene installato sia sul Watch sia (per la modalità Sonar) sull'iPhone — ogni dispositivo legge però il proprio microfono.

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

> Il nome interno della categoria (`emergency`/`danger`/`home`/`attention`) è la chiave usata per salvataggio e comunicazione tra i dispositivi e **non cambia**; i nomi leggibili e i colori sono definiti in un unico punto per app (`SoundCategory`).

### 🎯 Modalità Tracking (sonar aptico sul Watch)
Toccando l'icona di un suono rilevato si entra in **Tracking**: il Watch emette un pattern aptico la cui **intensità segue quanto il suono è forte/presente** in quel momento, per aiutare a localizzarne la sorgente spostandosi verso dove la vibrazione cresce. Dettagli:
- Quando il suono target sparisce la vibrazione si zittisce (gating sulla confidence), anche se il rumore di fondo resta alto.
- **Ri-tocco dell'emoji** → ferma il Tracking.
- **Auto-stop dopo 5 s** senza il suono target.
- Sul Watch l'intensità è approssimata da preset aptici (CoreHaptics non esiste su watchOS): per la vibrazione **a intensità continua** c'è la modalità Sonar **su iPhone** (vedi sotto), richiamabile col pulsante **"Localizza su iPhone"**.

### 🗂️ Storico locale "Smart Stack"
Sotto la schermata principale c'è uno **storico a colpo d'occhio** in stile Smart Stack del quadrante: a riposo non si vede (resta l'orecchio + una freccia), e **trascinando su con la Digital Crown** le card dei suoni rilevati salgono una a una. Raggruppato per tipo di suono, con colore di gravità e conteggio. È volutamente minimale: lo storico completo e ricco vive nell'app iPhone (il Watch continua comunque a inviarle ogni evento).

### ⏱️ Ascolto in background (sessione estesa)
- L'ascolto parte **automaticamente** all'apertura dell'app.
- `WKExtendedRuntimeSession` (tipo **Self Care**) mantiene il microfono attivo **anche a polso abbassato** o usando altre app (~30 min, con rinnovo trasparente).
- Alla scadenza: vibrazione di avviso; basta **ritoccare l'orecchio** per riprendere.
- Se la sessione cade per errori esterni (es. debugger collegato), l'app prova a **riavviarla da sola**.

### 📲 Notifiche
- Se un suono viene rilevato mentre l'app è **in background**, arriva una **notifica locale** con il nome del suono.
- Se l'app è **in primo piano**, la notifica è soppressa (vedi già l'alert visivo).

### 🖐️ Gesture
- **Double Tap** (pizzico pollice-indice, Series 9+): chiude un alert attivo o riavvia la sessione se scaduta.
- **Tap sullo schermo**: chiude l'alert corrente.
- **Digital Crown / trascinamento**: rivela lo storico Smart Stack.

### 🎨 Interfaccia
Schermata unica a strati:
1. **Stato d'ascolto** (icona `ear`/`ear.and.waveform`): tocca per accendere/spegnere; sotto, lo storico Smart Stack da rivelare scorrendo.
2. **Suono rilevato** — copre tutto con sfondo pieno colorato per gravità: tocca l'icona per il **Tracking sul Watch**, oppure premi **"📱 Localizza su iPhone"** per delegare la localizzazione all'iPhone.

---

## 📱 App iPhone companion — Funzionalità

L'app companion (`NotifEar/`) ha due tab — **Suoni** e **Storico** — più la **schermata Sonar** che compare su richiesta (handoff dal Watch).

### ➕ Crea e registra
- Crei un suono personalizzato (nome + categoria di gravità).
- Registri **più campioni** dello stesso suono (da distanze e volumi diversi: più varietà = riconoscimento migliore), li riascolti, ne elimini singoli.

### 🧪 Addestramento on-device
- Pulsante **"Addestra e invia al Watch"**: addestra un classificatore con **Create ML Components** (iOS 16+) **direttamente sull'iPhone** (nessun Mac), lo compila in `.mlmodelc`, ne tiene una **copia locale** (per la modalità Sonar) e lo spedisce al Watch.
- Servono **almeno 2 categorie/suoni**. Suggerimento: crea anche un suono **"rumore di fondo"** con campioni d'ambiente e tienilo **SPENTO** — serve come classe negativa per ridurre i falsi allarmi, ma non deve avvisare.

### 🔀 Sostituzione completa
Ogni "Addestra e invia" **sostituisce integralmente** il modello e le preferenze (non si somma al precedente): i suoni eliminati spariscono davvero dal modello personalizzato.

### 🎚️ Interruttore "Avvisa"
Per ogni suono c'è un toggle: se spento, il sistema **riconosce comunque** quel suono ma **non avvisa**. Le modifiche all'interruttore arrivano al Watch **subito**, senza riaddestrare.

### 🗂️ Storico
I suoni rilevati dal Watch vengono inviati all'iPhone e raccolti nello **Storico**, raggruppati per sequenze consecutive, con colore della categoria e swipe-to-delete.

### 🛡️ Anti falsi positivi (suoni custom)
Il riconoscimento dei suoni personalizzati è volutamente conservativo: confidenza alta sulla classe vincente, distacco netto dalla seconda, **conferma sostenuta** su più finestre consecutive e cooldown tra due avvisi — così un picco isolato non fa scattare l'allarme.

---

## 📡 Modalità Sonar su iPhone (novità)

Localizzazione tattile di precisione, attivata **solo a chiamata** dal Watch (l'iPhone non ascolta mai da solo — la "sentinella" resta il Watch).

**Flusso:**
1. Sul Watch, sul suono riconosciuto, premi **"Localizza su iPhone"**.
2. Il Watch invia all'iPhone il bersaglio (etichetta + chiavi di riconoscimento) via WatchConnectivity; l'iPhone (svegliato in background) posta una **notifica locale**.
3. **Tocchi la notifica** → si apre a tutto schermo la schermata Sonar, già agganciata a quel suono.
4. L'iPhone riconosce lo **stesso suono** (modello di sistema + copia locale del modello custom) e vibra.

**Vibrazione "a sensore di parcheggio"** (`UIImpactFeedbackGenerator`, controllo d'intensità granulare): **intensità e frequenza** degli impulsi crescono insieme col volume — suono debole → impulsi lievi e radi, suono vicino → impulsi forti e fitti. Ti sposti verso dove la vibrazione si fa più intensa/rapida.

**Comportamenti:**
- **Auto-stop dopo 5 s** senza il suono; stop anche al **ri-tocco dell'emoji** o con la **X**.
- Mentre stai localizzando un suono, quel suono **non viene ri-annunciato** (su Watch e iPhone); solo un suono *diverso* fa scattare un nuovo avviso. Alla fine del sonar l'iPhone avvisa il Watch che riprende ad annunciarlo.

> **Direzione del suono: non disponibile.** iOS non espone i microfoni grezzi sincronizzati, quindi non è possibile una vera stima della direzione: il sonar guida **per intensità** (avvicinandosi), non per verso.

---

## 🔁 Flussi tra i dispositivi (WatchConnectivity)

```
iPhone                                               Watch
──────                                               ─────
1. crei un suono + registri campioni
2. "Addestra e invia"
   → addestra (.mlmodelc) on-device + copia locale
   → transferFile(modello + preferenze)  ───────►  riceve, ricostruisce e installa il modello
                                                     affianca la richiesta custom al sistema
3. sposti l'interruttore "Avvisa"
   → updateApplicationContext(preferenze) ───────►  aggiorna le preferenze al volo
                                          ◄───────  4. al rilevamento: transferUserInfo(evento) → Storico

   ── Sonar (handoff) ──
                                          ◄───────  premi "Localizza su iPhone": sendMessage(bersaglio)
5. notifica locale → tap → schermata Sonar
6. fine sonar: sendMessage("sonarEnded") ───────►  riprende ad annunciare quel suono
```

Canali: `transferFile` per il modello (background), `updateApplicationContext` per le preferenze (l'ultimo stato vince), `transferUserInfo` per gli eventi, `sendMessage` per l'handoff del sonar (sveglia l'app in background, con fallback in coda).

---

## 🏗️ Architettura

Pattern **MVVM**. Il progetto Xcode `NotifEar.xcodeproj` contiene **due target** (`NotifEar` iPhone, `NotifEar Watch App`) — struttura standard Apple per un'app Watch con companion iPhone. Il progetto usa le **cartelle sincronizzate** di Xcode 16 (i file in una cartella appartengono automaticamente al rispettivo target).

### Watch App
| File | Ruolo |
|:---|:---|
| `NotifEarApp.swift` | Entry point → `ContentView`. |
| `ContentView.swift` | Schermata principale (stato d'ascolto) + storico Smart Stack sovrapposto + overlay del suono rilevato (tap icona → Tracking; pulsante "Localizza su iPhone"). |
| `SoundAnalyzerViewModel.swift` | Cuore: audio engine, classificatore di sistema + custom, categorie/colori/haptics, sessione estesa, notifiche, target del tracking, soppressione re-trigger. |
| `TrackingService.swift` · `TrackingView.swift` | Modalità Tracking (sonar aptico) di un suono target: gating, auto-stop 5 s, ri-tocco per fermare. |
| `HistoryStackView.swift` · `WatchHistoryStore.swift` | Storico locale "Smart Stack" (rivelato con la Corona) e relativo store minimale. |
| `CustomModelStore.swift` | Salva/installa il modello custom (`.mlmodelc`) e ne crea la richiesta di classificazione. |
| `CustomSoundConfigStore.swift` | Preferenze per-suono (avvisa sì/no + categoria) ricevute dall'iPhone. |
| `WatchModelReceiver.swift` | Lato Watch di WatchConnectivity: riceve modello/preferenze, invia gli eventi, riceve "fine sonar". |
| `ModelPackaging.swift` | Pacchettizza/ricostruisce la cartella `.mlmodelc` per il transfer. |

### App iPhone companion
| File | Ruolo |
|:---|:---|
| `NotifEarPhoneApp.swift` | Entry point. `TabView` "Suoni" + "Storico"; presenta la schermata Sonar (overlay) sull'handoff. |
| `PhoneRootView.swift` | Elenco suoni, toggle "Avvisa", swipe-elimina, "Addestra e invia", stato connessione; include `AddSoundView` e l'enum `SoundCategory`. |
| `RecordSampleView.swift` | Registrazione, riascolto ed eliminazione dei campioni di un suono. |
| `CustomSoundStore.swift` | Modello + persistenza dei suoni personalizzati e dei campioni. |
| `CustomSoundTrainer.swift` | Addestramento on-device (Create ML Components) e compilazione in `.mlmodelc`. |
| `PhoneConnectivityManager.swift` | Lato iPhone di WatchConnectivity: invia modello/preferenze, riceve eventi e l'handoff del sonar, posta la notifica, segnala la fine sonar. |
| `DetectionHistoryStore.swift` · `HistoryView.swift` | Storico dei rilevamenti ricevuti dal Watch. |
| `SampleRecorder.swift` · `SamplePlayer.swift` | Registrazione e riproduzione audio dei campioni. |
| `ModelPackaging.swift` | Gemello del Watch: pacchettizzazione del modello. |
| **Modalità Sonar:** | |
| `SonarTarget.swift` | Il "bersaglio" del sonar (etichetta, icona, categoria, chiavi di gating), serializzabile per WatchConnectivity e notifica. |
| `PhoneCustomModelStore.swift` | Gemello iOS di `CustomModelStore`: copia locale del modello custom per il riconoscimento sull'iPhone. |
| `PhoneSoundRecognizer.swift` | Motore di riconoscimento iOS (sistema + custom): pubblica RMS e confidence del target per il gating. |
| `PhoneSonarController.swift` | Gemello iOS di `TrackingService`: envelope/gating, calcola il `liveLevel` e pilota la vibrazione. |
| `SonarHapticEngine.swift` | Vibrazione "a sensore di parcheggio" via `UIImpactFeedbackGenerator` (intensità + frequenza ∝ volume). |
| `PhoneSonarView.swift` | UI della schermata Sonar (icona che pulsa col volume, onde, "muoviti per localizzare"). |

---

## ⚙️ Configurazione per sviluppatori

### Firma e Signing
Il `DEVELOPMENT_TEAM` nel progetto è vuoto. Ogni collaboratore imposta il proprio Team nel tab **Signing & Capabilities** di Xcode (per **entrambi** i target).

### Background Modes (Watch — obbligatorio su device fisico)
Target **NotifEar Watch App** → **Signing & Capabilities** → **+ Capability** → **Background Modes**:
1. ✅ **Audio**
2. ✅ **Extended Runtime Session** → **"Self Care"**

### Permessi microfono e notifiche
Entrambe le app usano il microfono: `NSMicrophoneUsageDescription` è presente negli Info.plist di **iPhone** (registrazione campioni + Sonar) e **Watch** (ascolto). L'iPhone richiede a runtime l'autorizzazione alle **notifiche** (per l'handoff del sonar).

### Vibrazione durante la registrazione (modalità Sonar)
iOS **silenzia gli haptic mentre il microfono registra** (per non far entrare il ronzio nell'audio). Il Sonar gira col mic attivo, quindi la sessione audio chiama `setAllowHapticsAndSystemSoundsDuringRecording(true)` (categoria `.playAndRecord`): senza questa riga la vibrazione **non parte**.

### Protezione file di progetto
Per non committare il proprio Team ID personale:
```bash
git update-index --assume-unchanged NotifEar.xcodeproj/project.pbxproj
```
> Se si aggiungono nuovi file al progetto, sbloccare con `--no-assume-unchanged`, committare con `git add -p` (escludendo la riga `DEVELOPMENT_TEAM`), poi ribloccare. *(Con le cartelle sincronizzate di Xcode 16, i nuovi file `.swift` in `NotifEar/` o `NotifEar Watch App/` entrano nel target senza modificare il pbxproj.)*

---

## 📋 Stato delle funzionalità

| Funzionalità | Stato |
|:---|:---|
| Riconoscimento on-device (sistema ~300 suoni) | ✅ |
| Suoni personalizzati (addestramento iPhone → Watch) | ✅ |
| Alert Watch: vibrazione per categoria + visivo + notifica | ✅ |
| Tracking/sonar aptico sul Watch (intensità a preset) | ✅ |
| Storico: completo su iPhone, "Smart Stack" sul Watch | ✅ |
| **Sonar su iPhone** (handoff, vibrazione granulare "metal detector", auto-stop, anti re-trigger) | ✅ |

---

## 📌 Requisiti

- **Apple Watch**: watchOS **26.4+** (Double Tap su Series 9 / Ultra 2 e successivi)
- **iPhone companion**: iOS **18.0+** (l'addestramento on-device usa Create ML Components, iOS 16+)
- **iPhone e Watch abbinati** per suoni personalizzati e modalità Sonar
- **Xcode 26+** (SDK iOS 18 / watchOS 26)

---

## 📄 File di riferimento

| File | Descrizione |
|:---|:---|
| `SOUND_LABELS.md` | Catalogo curato dei suoni riconoscibili con traduzione italiana |
| `all_labels.txt` | Lista completa dei ~300 identifier del modello Apple |
