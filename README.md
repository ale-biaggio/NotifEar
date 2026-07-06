# NotifEar

NotifEar è un prototipo di interfaccia multimodale per Apple Watch pensato per supportare persone sorde o ipoudenti nella percezione di suoni ambientali rilevanti. L'app Watch ascolta l'ambiente, riconosce suoni in tempo reale con classificazione on-device e restituisce feedback visivi, aptici e notifiche locali.

Il sistema include anche un'app companion per iPhone. L'iPhone permette di creare suoni personalizzati, registrare esempi audio, addestrare un classificatore locale e trasferirlo al Watch. Inoltre può ricevere dal Watch un target sonoro e attivare una modalità Sonar con feedback aptico più granulare.

## Obiettivo

NotifEar esplora una soluzione indossabile e autonoma per rendere più accessibili eventi sonori quotidiani come sirene, campanelli, clacson, urla, allarmi e suoni personalizzati. L'interazione combina:

- output visivo, con colore e icona proporzionati alla gravità del suono;
- output aptico, con pattern differenziati per categoria e urgenza;
- notifiche locali, quando l'app non è in primo piano;
- input gestuale su Watch, tramite tap, Digital Crown e Double Tap;
- continuità Watch-iPhone, tramite WatchConnectivity;
- modalità Sonar, in cui il feedback cambia in base alla presenza del suono target.

## Funzionamento generale

Sul Watch il riconoscimento audio usa `SoundAnalysis` con `SNAudioStreamAnalyzer`. La pipeline elabora il flusso del microfono con due classificatori:

| Classificatore | Ruolo |
|:---|:---|
| Sistema Apple | Riconosce gli identifier del modello `SNClassifySoundRequest` Version 1. |
| Custom | Riconosce i suoni addestrati dall'utente sull'iPhone e trasferiti al Watch. |

Il classificatore custom è opzionale. Quando è disponibile, viene affiancato al classificatore di sistema sullo stesso input audio. Entrambi girano on-device e non richiedono rete.

## App Watch

L'app Watch è il componente principale del sistema. All'apertura avvia l'ascolto e mantiene una sessione estesa per continuare a usare il microfono anche a polso abbassato, nei limiti concessi da watchOS.

Le funzioni principali sono:

- riconoscimento audio in tempo reale con `AVAudioSession`, `AVAudioEngine` e `SNAudioStreamAnalyzer`;
- classificazione di suoni di sistema e suoni custom;
- alert visivo a schermo pieno con colore, icona e nome del suono;
- pattern aptici differenziati per livello di urgenza;
- notifiche locali quando l'app è in background;
- storico sintetico sul Watch, navigabile con Digital Crown;
- attivazione della modalità Sonar per localizzare in modo esplorativo il suono rilevato;
- handoff del Sonar all'iPhone quando serve un feedback aptico più fine.

## Categorie di suono

I suoni sono organizzati in quattro categorie. La stessa scala viene applicata sia ai suoni di sistema sia ai suoni custom configurati dall'utente.

| Gravità | Categoria interna | Esempi | Feedback Watch |
|:---|:---|:---|:---|
| Emergenza | `emergency` | sirena, ambulanza, allarme incendio, rilevatore di fumo | rosso, 3 vibrazioni rapide |
| Suono urgente | `danger` | urlo, grido, clacson | arancione, 2 vibrazioni |
| Suono domestico | `home` | campanello, bussare, telefono | giallo, 1 tocco leggero |
| Suono generico | `attention` | pianto, cane, abbaio | verde, 1 vibrazione |

Gli identifier di sistema intercettati esplicitamente sono documentati in `SOUND_LABELS.md`.

## Wrist Sonar

Quando il Watch rileva un suono, l'utente può entrare nella modalità Sonar. In questa modalità il sistema non stima direttamente la direzione della sorgente sonora. L'utente esplora l'ambiente muovendosi: il feedback diventa più evidente quando il suono target è più presente.

Sul Watch il Sonar usa:

- gating sulla confidence del target, per evitare che rumore generico mantenga attiva la vibrazione;
- cadenza aptica fissa;
- preset aptici via `WKHapticType`, con forza crescente in base al livello del suono;
- auto-stop dopo alcuni secondi senza target;
- uscita tramite X, tap sullo sfondo o nuovo tap sull'icona del suono.

Questa scelta rispetta i vincoli di watchOS, dove non è disponibile un controllo continuo dell'ampiezza aptica tramite CoreHaptics.

## App iPhone companion

L'app iPhone estende il sistema Watch con tre funzioni principali:

- creazione e gestione di suoni personalizzati;
- addestramento on-device di un classificatore audio tramite Create ML Components;
- Sonar su iPhone, attivato dal Watch per lo stesso suono target.

Per i suoni personalizzati, l'utente registra più campioni per ogni classe. Il sistema richiede almeno due classi e un numero minimo di esempi validi. Dopo l'addestramento, il modello viene compilato in `.mlmodelc`, conservato localmente per il Sonar iPhone e trasferito al Watch.

Ogni suono custom ha anche un interruttore "Avvisa". Se disattivato, il suono può restare nel modello ma non genera alert. Questo permette, ad esempio, di usare una classe di rumore di fondo come classe negativa.

## Sonar su iPhone

Il Sonar iPhone viene attivato dal Watch tramite WatchConnectivity. Il Watch invia all'iPhone il target sonoro, cioè etichetta, categoria e chiavi di riconoscimento. L'iPhone apre una sessione di riconoscimento sul proprio microfono e restituisce feedback aptico tramite `UIImpactFeedbackGenerator`.

Rispetto al Watch, l'iPhone consente un controllo più granulare del feedback. Nel Sonar iPhone intensità e frequenza degli impulsi possono aumentare insieme al livello del suono. Anche in questo caso la direzione non viene stimata in modo esplicito: l'utente si orienta cercando la posizione in cui il feedback cresce.

## Comunicazione Watch-iPhone

La sincronizzazione tra i dispositivi usa WatchConnectivity:

| Canale | Uso |
|:---|:---|
| `transferFile` | invio del modello custom e delle preferenze al Watch |
| `updateApplicationContext` | aggiornamento delle preferenze dei suoni custom |
| `transferUserInfo` | invio degli eventi rilevati dal Watch allo storico iPhone |
| `sendMessage` | handoff del target Sonar e segnalazione di fine Sonar |

Il Watch resta il dispositivo principale per l'ascolto continuo. L'iPhone interviene per addestramento, storico completo e localizzazione tattile più granulare.

## Architettura

Il progetto usa un'organizzazione MVVM con due target principali:

| Target | Ruolo |
|:---|:---|
| `NotifEar Watch App` | ascolto ambientale, alert, feedback aptico, Sonar Watch, storico sintetico |
| `NotifEar` | gestione suoni custom, addestramento, storico completo, Sonar iPhone |

File principali lato Watch:

| File | Responsabilità |
|:---|:---|
| `ContentView.swift` | schermata principale, alert e accesso al Sonar |
| `SoundAnalyzerViewModel.swift` | audio engine, classificatori, categorie, haptics, notifiche e sessione estesa |
| `TrackingService.swift` | logica del Sonar Watch, gating, envelope e auto-stop |
| `TrackingView.swift` | interfaccia del Sonar Watch |
| `WatchModelReceiver.swift` | ricezione modello custom, preferenze ed eventi WatchConnectivity |
| `CustomModelStore.swift` | installazione e caricamento del modello custom sul Watch |
| `WatchHistoryStore.swift` | storico locale sintetico |

File principali lato iPhone:

| File | Responsabilità |
|:---|:---|
| `PhoneRootView.swift` | gestione suoni custom e invio al Watch |
| `RecordSampleView.swift` | registrazione e riascolto dei campioni |
| `CustomSoundTrainer.swift` | addestramento on-device del classificatore custom |
| `PhoneConnectivityManager.swift` | comunicazione con il Watch e notifiche di handoff |
| `DetectionHistoryStore.swift` | storico completo dei rilevamenti |
| `PhoneSoundRecognizer.swift` | riconoscimento audio per il Sonar iPhone |
| `PhoneSonarController.swift` | gating e controllo del feedback Sonar su iPhone |
| `SonarHapticEngine.swift` | generazione degli impulsi aptici su iPhone |

## Stato del progetto

| Funzionalità | Stato |
|:---|:---|
| Riconoscimento on-device di suoni di sistema | Completato |
| Suoni personalizzati con addestramento su iPhone | Completato |
| Trasferimento modello custom al Watch | Completato |
| Alert Watch visivi, aptici e notifiche locali | Completato |
| Wrist Sonar su Watch | Completato |
| Sonar su iPhone tramite handoff dal Watch | Completato |
| Storico sintetico su Watch e completo su iPhone | Completato |

## Requisiti tecnici

- Apple Watch con watchOS 26.4 o successivo.
- iPhone con iOS 18.0 o successivo.
- iPhone e Apple Watch abbinati per suoni custom, storico completo e Sonar iPhone.
- Xcode 26 o successivo per compilare il progetto.

## File di riferimento

| File | Descrizione |
|:---|:---|
| `SOUND_LABELS.md` | suoni di sistema intercettati esplicitamente da NotifEar |

## Licenza

Il codice sorgente è reso disponibile solo per la valutazione accademica del progetto. Non è concesso il riuso, la modifica o la redistribuzione senza autorizzazione scritta degli autori. Vedi `LICENSE`.
