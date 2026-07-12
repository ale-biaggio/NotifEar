# NotifEar

NotifEar è un prototipo di interfaccia multimodale per Apple Watch progettato per supportare persone sorde e ipoudenti nella percezione di suoni ambientali rilevanti. Il Watch ascolta l'ambiente, classifica i suoni interamente on-device e traduce ogni evento in feedback visivo e aptico. Un'app companion per iPhone permette inoltre di creare suoni personalizzati, consultare lo storico completo e proseguire la localizzazione tramite una modalità Sonar più granulare.

Il progetto è stato sviluppato per l'esame di Multimodal Interaction della laurea magistrale in Cybersecurity, Sapienza Università di Roma.

## Idea e obiettivo

NotifEar applica il principio di sensory substitution: un'informazione normalmente uditiva viene resa percepibile attraverso vista e tatto. Il sistema non si limita a segnalare che è presente un suono, ma ne comunica anche identità, categoria di urgenza, persistenza e, nella modalità Sonar, intensità relativa durante l'esplorazione dello spazio.

L'interazione combina:

- output visivo, mediante colore, icona, nome del suono e animazioni;
- output aptico, mediante pattern codificati per categoria;
- notifiche locali quando l'app Watch non è in primo piano;
- input gestuale tramite tap, Double Tap e Digital Crown;
- continuità Watch-iPhone tramite WatchConnectivity;
- esplorazione fisica nel Wrist Sonar, dove movimento, vista e tatto concorrono alla localizzazione.

Il Watch resta il dispositivo principale e autonomo per l'ascolto. L'iPhone è un'estensione richiesta solo per addestramento dei suoni custom, storico completo e Sonar più granulare.

## Contributi principali

I tre elementi caratterizzanti del progetto sono:

1. riconoscimento audio interamente on-device direttamente su watchOS;
2. codifica aptica dell'urgenza con pattern differenziati e ripetuti fino al riconoscimento dell'alert;
3. Wrist Sonar solo software, senza hardware esterno e senza stima esplicita della direzione.

La multimodalità opera su più livelli: ridondanza tra colore e vibrazione, complementarità tra identità e urgenza, input gestuale, fusione tra movimento e feedback nel Sonar e continuità tra Watch e iPhone.

## Architettura generale

Il progetto contiene due target Swift/SwiftUI organizzati secondo un'impostazione MVVM:

| Target | Ruolo |
|:---|:---|
| `NotifEar Watch App` | ascolto ambientale, classificazione, alert, feedback aptico, Wrist Sonar e storico sintetico |
| `NotifEar` | creazione dei suoni custom, registrazione, training, storico completo e Sonar iPhone |

La pipeline audio del Watch è:

```text
Microfono → AVAudioSession → AVAudioEngine → SNAudioStreamAnalyzer
                                          ├─ classificatore Apple
                                          └─ classificatore custom opzionale
```

I due classificatori ricevono lo stesso flusso audio e funzionano interamente sul dispositivo, senza inviare registrazioni o risultati a server esterni.

### Classificatore Apple

NotifEar usa `SNClassifySoundRequest` Version 1, il modello di SoundAnalysis pre-addestrato da Apple su circa 300 classi. Il modello produce risultati per molte categorie, ma l'app genera alert solo per un sottoinsieme esplicitamente mappato e documentato in `SOUND_LABELS.md`.

### Classificatore custom

Il classificatore custom è addestrato dall'utente sull'iPhone tramite Create ML Components. Dopo il training viene compilato in `.mlmodelc`, conservato localmente anche per il Sonar iPhone e trasferito al Watch, dove viene eseguito in parallelo al classificatore Apple.

## Categorie, colori e pattern aptici

Suoni Apple e suoni custom condividono le stesse quattro categorie. Il colore viene mantenuto coerente nell'alert Watch, nel Sonar, nello storico Watch, nello storico iPhone e nella gestione dei suoni custom.

| Gravità | Valore interno | Colore | Esempi Apple | Pattern aptico Watch |
|:---|:---|:---|:---|:---|
| Emergenza | `emergency` | Rosso | ambulanza, sirena, allarme incendio, rilevatore di fumo | 2 × `.notification`, a 0 e 0,8 s |
| Suono urgente | `danger` | Arancione | urlo, grido, clacson | 3 × `.directionUp`, a 0, 0,3 e 0,6 s |
| Suono domestico | `home` | Giallo | campanello, bussare, telefono | 3 × `.click`, a 0, 0,3 e 0,6 s |
| Suono generico | `attention` | Verde | pianto, cane, abbaio | 1 × `.click` |

I pattern sono stati regolati con prove sul Watch reale. La scala non dipende solo dal numero di colpi: usa anche il carattere del preset e il ritmo. Il rosso impiega il preset percepito come più forte, l'arancione una tripletta marcata, il giallo una tripletta leggera e il verde un singolo richiamo discreto.

### Ripetizione fino al riconoscimento

Il pattern completo della categoria parte subito alla creazione dell'alert e ricomincia ogni 2 secondi. La distanza di 2 secondi è misurata tra l'inizio di due cicli consecutivi; gli intervalli interni al pattern restano quelli indicati nella tabella.

La ripetizione continua solo mentre l'episodio è attivo e non è stato riconosciuto dall'utente. Si interrompe immediatamente quando:

- l'utente chiude l'alert con un tap;
- l'utente chiude l'alert con il Double Tap;
- l'utente entra nel Sonar;
- il suono termina secondo la politica di fine episodio;
- l'ascolto viene disattivato o la sessione termina.

Il loop è cancellabile: anche i colpi interni già programmati vengono annullati, evitando vibrazioni residue dopo l'interazione.

## Dal risultato ML all'episodio sonoro

NotifEar separa due problemi:

- il filtraggio del riconoscimento, specifico per ciascun classificatore;
- la gestione dell'evento e dell'alert, condivisa tra suoni Apple e custom.

### Filtri di ingresso e mantenimento

| Pipeline | Condizioni di ingresso | Condizione di mantenimento |
|:---|:---|:---|
| Apple | confidence ≥ 0,55 | confidence ≥ 0,35 |
| Custom | confidence ≥ 0,85, margine ≥ 0,30 sulla seconda classe e 3 risultati consecutivi validi | confidence ≥ 0,60 |

Le soglie d'ingresso sono più severe di quelle di mantenimento. Questa isteresi evita che piccole oscillazioni, per esempio 0,56 → 0,53 → 0,57, facciano apparire e scomparire rapidamente l'alert.

Il filtro custom è più severo perché il modello viene addestrato con pochi esempi personali ed è più esposto ai falsi positivi. Il margine richiede che la classe vincente sia nettamente separata dalla seconda classificata; i tre hit consecutivi richiedono conferma temporale.

### Macchina a stati dell'episodio

Il sistema mantiene un solo episodio sonoro attivo alla volta:

```text
Assente
  ↓ superamento dei filtri d'ingresso
Rilevato / alert visibile / vibrazione ciclica
  ├─ nuovo risultato sopra la soglia d'uscita → episodio mantenuto
  ├─ tap, Double Tap o Sonar → episodio riconosciuto, alert e vibrazioni fermati
  └─ assenza sotto soglia per 2,5 s → episodio concluso
```

Quando un risultato mantiene l'episodio, il tempo dell'ultima presenza viene aggiornato. Se il suono scende sotto la soglia, l'episodio non termina immediatamente: deve rimanere assente per almeno 2,5 secondi. Questa tolleranza gestisce pause naturali e oscillazioni della confidence.

### Nessun cooldown temporale fisso

NotifEar non usa più un cooldown del tipo “attendi 8 secondi e poi consenti un nuovo alert”. Un cooldown fisso farebbe riapparire una sirena continua allo scadere del timer.

La deduplicazione è invece basata sull'episodio:

1. il primo riconoscimento crea un solo alert;
2. alert, vibrazione iniziale, notifica locale e voce nello storico vengono generati una sola volta;
3. se l'utente chiude l'alert, lo stesso episodio continua a essere monitorato internamente ma non riapre l'interfaccia e non vibra più;
4. solo dopo 2,5 secondi di assenza l'episodio viene concluso;
5. una rilevazione successiva può quindi creare un nuovo episodio.

Questo comportamento impedisce sia la duplicazione continua di una sirena persistente sia la riapertura immediata dell'alert dopo un tap.

## Alert visivo e notifiche locali

Quando nasce un episodio, l'alert Watch mostra a schermo pieno:

- colore o gradiente della categoria;
- icona o emoji del suono;
- nome del suono;
- accesso al Wrist Sonar.

L'alert non ha una durata fissa di 5 secondi: rimane visibile finché il suono continua, salvo riconoscimento manuale o ingresso nel Sonar. Se il suono termina senza interazione, scompare automaticamente dopo la tolleranza di 2,5 secondi.

Quando l'app Watch è attiva in primo piano viene usato soltanto l'alert in-app, evitando una notifica di sistema sovrapposta. Se l'app non è attiva, viene inviata una notifica locale con il nome del suono. La notifica locale viene creata una sola volta per episodio.

## Gesture e controllo contestuale

Il Double Tap di watchOS è associato all'azione primaria della schermata corrente:

| Contesto | Azione del Double Tap |
|:---|:---|
| Alert visibile | riconosce e chiude l'alert, interrompendo il loop aptico |
| Wrist Sonar aperto | chiude il Sonar e interrompe il tracking |
| Schermata principale | attiva o disattiva l'ascolto |

Gli stessi flussi principali sono accessibili anche tramite tap sullo schermo. La Digital Crown permette di esplorare lo storico sintetico sul Watch.

## Wrist Sonar sul Watch

Il Wrist Sonar aiuta l'utente a localizzare in modo esplorativo il suono appena rilevato. Non calcola un angolo e non mostra una freccia: l'utente muove polso e corpo e cerca la posizione nella quale il feedback diventa più evidente.

Il Sonar combina due grandezze:

- confidence del classificatore, usata come gating per verificare che il target sia presente;
- livello RMS del microfono, usato come stima relativa dell'intensità o vicinanza.

### Politica del Sonar Watch

- il controllo viene aggiornato ogni 0,1 secondi;
- la confidence viene smussata e deve raggiungere 0,40;
- il feedback aptico ha cadenza fissa di circa 0,45 secondi;
- il volume non cambia la frequenza dei colpi, ma seleziona un preset progressivamente più forte;
- la scala aptica è `.click` → `.start` → `.notification` → `.failure`;
- sotto un livello minimo il Sonar resta silenzioso;
- dopo 5 secondi senza target il tracking si arresta automaticamente;
- i cerchi concentrici sono sincronizzati con i colpi aptici.

La cadenza fissa è una scelta coerente con i vincoli di watchOS: CoreHaptics non è disponibile sul Watch e non è possibile modulare continuamente l'ampiezza. La forza viene quindi resa mediante preset `WKHapticType` discreti.

L'utente può uscire tramite il controllo di chiusura, un tap sull'area prevista o il Double Tap. Entrando nel Sonar, l'episodio originale viene considerato riconosciuto: il precedente alert non riappare mentre si localizza lo stesso suono.

## Handoff al Sonar iPhone

Dal Wrist Sonar è disponibile il comando “Passa a iPhone”. Il Watch invia all'iPhone:

- etichetta e categoria;
- icona;
- identifier Apple associati;
- eventuale label del modello custom.

L'iPhone pubblica una notifica locale. Toccandola si apre il Sonar già configurato sul target corretto. Durante il Sonar iPhone lo stesso suono viene temporaneamente soppresso dagli alert Watch, evitando duplicazioni; la soppressione termina alla chiusura del Sonar o, come sicurezza, dopo 60 secondi.

### Sonar iPhone

Il Sonar iPhone riutilizza il modello Apple e, quando necessario, la copia locale del classificatore custom. Anche qui la confidence verifica la presenza del target e il livello RMS controlla il feedback.

- controllo ogni 0,1 secondi;
- soglia di confidence 0,40;
- auto-stop dopo 5 secondi senza target;
- smussamento separato per salita e discesa del livello, per avere una risposta pronta ma non instabile;
- feedback mediante `UIImpactFeedbackGenerator`;
- intensità crescente con il livello;
- frequenza degli impulsi variabile approssimativamente tra 0,6 e 13 Hz.

A differenza del Watch, sull'iPhone intensità e frequenza possono crescere insieme. Anche il Sonar iPhone non stima una direzione esplicita: l'utente si orienta cercando il punto nel quale il feedback aumenta.

## Suoni personalizzati

L'iPhone permette di creare categorie acustiche personali, per esempio citofono, elettrodomestico o segnale specifico dell'ambiente domestico.

### Creazione e categorie

Ogni suono custom ha:

- un nome univoco;
- una delle quattro categorie condivise, con etichetta e colore coerenti;
- un insieme di registrazioni;
- un interruttore “Avvisa”.

Il selettore propone:

| Etichetta | Valore | Colore |
|:---|:---|:---|
| Suono generico | `attention` | Verde |
| Suono domestico | `home` | Giallo |
| Suono urgente | `danger` | Arancione |
| Emergenza | `emergency` | Rosso |

La categoria selezionata determina sul Watch colore e pattern aptico esattamente come per i suoni Apple.

### Requisiti di training

Per avviare il training servono:

- almeno due categorie di suono;
- nomi distinti, confrontati senza differenze di maiuscole o accenti;
- almeno due campioni audio validi per ogni categoria.

È consigliato aggiungere una categoria di rumore di fondo come classe negativa. Disattivando “Avvisa”, la classe resta nel modello e contribuisce alla discriminazione, ma non genera alert.

Ogni nuovo training sostituisce il modello custom precedente. Modello e configurazione vengono trasferiti al Watch; se il modello custom non è disponibile, la pipeline Apple continua a funzionare autonomamente.

## Storico

Ogni episodio viene registrato una sola volta, indipendentemente dalla durata del suono e dal numero di cicli aptici.

Sul Watch è disponibile uno storico sintetico navigabile con Digital Crown. Sull'iPhone è presente lo storico completo, sincronizzato dal Watch tramite WatchConnectivity. Eventi consecutivi con la stessa etichetta vengono raggruppati e possono essere espansi; è possibile eliminare singoli eventi, interi gruppi o cancellare tutto lo storico tramite il pulsante in fondo alla lista.

## WatchConnectivity

| Canale | Utilizzo |
|:---|:---|
| `transferFile` | trasferimento del modello custom compilato al Watch |
| `updateApplicationContext` | sincronizzazione delle preferenze, categorie e toggle “Avvisa” |
| `transferUserInfo` | trasferimento degli episodi allo storico iPhone |
| `sendMessage` | handoff del target Sonar e segnalazione della fine del Sonar |

La comunicazione con l'iPhone non è necessaria per il riconoscimento Apple e per gli alert principali del Watch.

## Sessione di ascolto

All'apertura, l'app Watch richiede il permesso del microfono e avvia automaticamente l'ascolto. Una `WKExtendedRuntimeSession` permette di continuare a utilizzare il microfono anche a polso abbassato, nei limiti temporali concessi da watchOS.

L'utente può fermare e riavviare l'ascolto dalla schermata principale tramite tap o Double Tap. Se la sessione estesa scade o viene soppressa dal sistema, l'app interrompe in modo coerente audio, episodio e feedback e mostra lo stato di sessione scaduta; l'utente può quindi riavviare l'ascolto.

## Multimodalità e concetti del corso

- **Post-WIMP:** l'interazione principale avviene su un wearable tramite audio ambientale, gesto, colore e tatto, senza paradigma desktop tradizionale.
- **Ridondanza:** colore e pattern aptico comunicano entrambi la categoria di urgenza.
- **Complementarità:** testo e icona comunicano l'identità, mentre colore e vibrazione aggiungono urgenza e persistenza.
- **Sensory substitution:** eventi uditivi vengono convertiti in stimoli visivi e tattili.
- **Fusione:** nel Sonar il movimento dell'utente, la confidence del classificatore, il livello audio e il feedback visivo-aptico concorrono alla localizzazione.
- **Gesture:** il Double Tap funziona come comando contestuale; il movimento di polso e corpo nel Sonar è manipolativo.
- **Continuità cross-device:** il Watch rileva e avvia il flusso, l'iPhone può proseguirlo con training, storico e feedback più granulare.

## Differenze rispetto al prototipo HCI precedente

NotifEar evolve un precedente prototipo Wear OS, ma introduce modifiche sostanziali:

- riscrittura completa in Swift per watchOS;
- classificazione e gestione degli alert direttamente sul Watch;
- categorie di urgenza con colori e pattern aptici differenziati;
- ripetizione aptica fino al riconoscimento dell'alert;
- suoni personalizzati addestrabili on-device;
- Wrist Sonar solo software;
- handoff al Sonar iPhone;
- storico sincronizzato tra dispositivi.

Il prototipo precedente disponeva già di una vibrazione, ma era indifferenziata. Non va quindi descritto come privo di feedback aptico.

## Limiti e scelte di scope

- NotifEar non stima esplicitamente la direzione della sorgente; la localizzazione è esplorativa.
- Sul Watch l'intensità aptica non è modulabile in continuo: vengono usati preset discreti.
- L'ascolto esteso resta soggetto ai limiti energetici e temporali imposti da watchOS.
- I suoni custom dipendono dalla qualità, quantità e varietà dei campioni registrati.
- Comandi vocali continui e live captioning sono esclusi perché watchOS non espone una pipeline Speech continua equivalente a quella iOS.
- Modalità contestuali adattive e localizzazione hardware TDOA sono fuori scope.

## Stato del progetto

| Funzionalità | Stato |
|:---|:---|
| Riconoscimento Apple on-device | Completato |
| Classificatore custom addestrato su iPhone | Completato |
| Ciclo di vita unificato per episodi | Completato |
| Alert visivo e loop aptico cancellabile | Completato |
| Double Tap contestuale | Completato |
| Storico Watch e iPhone | Completato |
| Wrist Sonar | Completato |
| Handoff e Sonar iPhone | Completato |

## Requisiti tecnici

- Apple Watch con watchOS 26.4 o successivo;
- iPhone con iOS 18.0 o successivo;
- Xcode 26 o successivo;
- iPhone e Watch abbinati per training, sincronizzazione dello storico e Sonar iPhone.

## File di riferimento

| File | Descrizione |
|:---|:---|
| `SOUND_LABELS.md` | identifier Apple intercettati esplicitamente e relativa mappatura |

## Licenza

Il codice sorgente è disponibile esclusivamente per la valutazione accademica del progetto. Non è consentito il riuso, la modifica o la redistribuzione senza autorizzazione scritta degli autori. Vedi `LICENSE`.
