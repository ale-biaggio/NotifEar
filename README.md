# 👂 NotifEar – Riconoscimento Suoni per Apple Watch

**NotifEar** è un'app standalone per **watchOS** pensata per aiutare le persone **ipoudenti o sorde** a percepire i suoni ambientali. Sfrutta il microfono dell'Apple Watch e il machine learning on-device per riconoscere suoni in tempo reale e avvisare l'utente tramite **vibrazioni aptiche**, **feedback visivo** e **notifiche locali**.

---

## ✨ Funzionalità

### 🎙️ Riconoscimento Audio in Tempo Reale
- Utilizza il framework nativo Apple **SoundAnalysis** con il modello predefinito **Version 1**, capace di riconoscere ~300 suoni diversi.
- L'analisi avviene interamente **on-device**, senza connessione internet.
- Pipeline audio: `AVAudioSession` → `AVAudioEngine` → `SNAudioStreamAnalyzer`.

### 🔔 Suoni Monitorati

L'app filtra un sottoinsieme specifico di suoni, organizzati in **4 categorie**:

| Categoria | Suoni | Icona | Vibrazione |
|:---|:---|:---|:---|
| 🚨 **Emergenza** | Sirena ambulanza, sirena generica, allarme incendio, rilevatore di fumo | 🚑 🚨 🔥 | 3 vibrazioni rapide |
| ⚠️ **Pericolo** | Urlo, grido, clacson | ⚠️ 🔊 🚗 | 2 vibrazioni |
| 🏠 **Casa** | Campanello, bussare, telefono, suoneria | 🔔 🚪 📞 | 1 vibrazione |
| 👶 **Attenzione** | Pianto neonato, pianto, cane, abbaio | 👶 😢 🐕 | 1 vibrazione |

### ⌚ Sessione Estesa (~30 minuti)
- L'ascolto parte **automaticamente** all'apertura dell'app, senza pulsanti.
- Usa `WKExtendedRuntimeSession` (tipo **Self Care**) per mantenere il microfono attivo **anche a polso abbassato** o mentre si usano altre app.
- Timer di countdown visibile nella seconda pagina con progress ring circolare.
- Alla scadenza: vibrazione di avviso e possibilità di riavviare la sessione.
- Se la sessione viene interrotta per errori esterni (es. debugger), l'app prova a **riavviarla automaticamente**.

### 📲 Notifiche Intelligenti
- Quando un suono viene rilevato e l'app è **in background** (es. stai usando un'altra app), ricevi una **notifica locale** con il nome del suono.
- Esempio: **"CLACSON" – "NotifEar ha rilevato il suono di un clacson!"**
- Se l'app è **in primo piano**, la notifica viene **soppressa** (vedi già l'alert visivo).

### 🖐️ Gesture
- **Double Tap** (pizzico pollice-indice, Series 9+): dismissare un alert sonoro attivo, oppure riavviare la sessione se scaduta.
- **Tap sullo schermo**: dismissare l'alert del suono corrente.

### 🎨 Interfaccia
- **Pagina 1** (default): animazione di ascolto con icona `ear.and.waveform`, sfondo a gradiente dinamico che cambia colore in base alla categoria del suono rilevato.
- **Pagina 2** (swipe a sinistra): timer circolare con minuti e secondi rimanenti, pulsante stop/riavvia.
- Navigazione tramite `TabView` con swipe orizzontale.

---

## 🏗️ Architettura

Pattern **MVVM** (Model-View-ViewModel):

| File | Ruolo |
|:---|:---|
| `NotifEarApp.swift` | Entry point. Crea il ViewModel condiviso e la TabView. |
| `ContentView.swift` | View principale con feedback visivo, animazioni e gesture. |
| `SessionView.swift` | View sessione con timer circolare e controlli. |
| `SoundAnalyzerViewModel.swift` | Logica: permessi, audio engine, ML, sessione estesa, haptics, notifiche. |

---

## ⚙️ Configurazione per Sviluppatori

### Firma e Signing
Il `DEVELOPMENT_TEAM` nel progetto è vuoto. Ogni collaboratore deve impostare il proprio Team nel tab **Signing & Capabilities** di Xcode.

### Background Modes (obbligatorio per device fisico)
Nel target **NotifEar Watch App** → **Signing & Capabilities** → **+ Capability** → **Background Modes**:
1. ✅ Spunta **Audio**
2. ✅ Spunta **Extended Runtime Session** → seleziona **"Self Care"**

### Protezione file di progetto
Per evitare di committare il proprio Team ID personale:
```bash
git update-index --assume-unchanged NotifEar.xcodeproj/project.pbxproj
```

> **Nota**: Se si aggiungono nuovi file al progetto, sbloccare temporaneamente con `--no-assume-unchanged`, committare con `git add -p` (per escludere la riga del DEVELOPMENT_TEAM), e poi ribloccare.

---

## 📋 Requisiti

- **watchOS 10.1+**
- Apple Watch Series 4+ (Series 9+ per Double Tap)
- Xcode 15+

---

## 📄 File di Riferimento

| File | Descrizione |
|:---|:---|
| `SOUND_LABELS.md` | Catalogo curato dei suoni riconoscibili con traduzione italiana |
| `all_labels.txt` | Lista completa dei ~300 identifier del modello Apple |