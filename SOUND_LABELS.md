# Suoni di sistema mappati in NotifEar

Questo file documenta gli identifier del classificatore Apple SoundAnalysis che NotifEar intercetta esplicitamente nella Watch App. Non è la lista completa dei suoni supportati dal modello Apple: il classificatore di sistema può riconoscere molte più classi, ma l'app genera alert solo per quelle mappate nel codice.

I suoni personalizzati addestrati dall'utente non compaiono qui, perché vengono creati e configurati dinamicamente dall'app iPhone.

## Emergenza

| Identifier | Etichetta in app | Feedback |
|:---|:---|:---|
| `ambulance_siren` | Ambulanza | Rosso, 3 vibrazioni rapide |
| `siren` | Sirena | Rosso, 3 vibrazioni rapide |
| `fire_alarm` | Allarme incendio | Rosso, 3 vibrazioni rapide |
| `smoke_detector` | Allarme fumo | Rosso, 3 vibrazioni rapide |

## Suono urgente

| Identifier | Etichetta in app | Feedback |
|:---|:---|:---|
| `scream` | Urlo rilevato | Arancione, 2 vibrazioni |
| `shout` | Grido rilevato | Arancione, 2 vibrazioni |
| `car_horn` | Clacson | Arancione, 2 vibrazioni |

## Suono domestico

| Identifier | Etichetta in app | Feedback |
|:---|:---|:---|
| `door_bell` | Campanello | Giallo, 1 tocco leggero |
| `doorbell` | Campanello | Giallo, 1 tocco leggero |
| `knock` | Bussano | Giallo, 1 tocco leggero |
| `telephone_bell` | Telefono | Giallo, 1 tocco leggero |
| `ringtone` | Telefono | Giallo, 1 tocco leggero |

## Suono generico

| Identifier | Etichetta in app | Feedback |
|:---|:---|:---|
| `baby_crying` | Pianto neonato | Verde, 1 vibrazione |
| `baby_cry` | Pianto neonato | Verde, 1 vibrazione |
| `crying` | Pianto | Verde, 1 vibrazione |
| `dog` | Cane | Verde, 1 vibrazione |
| `bark` | Abbaio | Verde, 1 vibrazione |

## Dove sono usati

La mappa runtime è definita in `NotifEar Watch App/SoundAnalyzerViewModel.swift`, nella proprietà `soundMap`. Più identifier possono puntare alla stessa etichetta visiva, per esempio `door_bell` e `doorbell` sono entrambi mostrati come "Campanello".
