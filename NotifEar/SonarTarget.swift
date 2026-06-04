//
//  SonarTarget.swift
//  NotifEar (iPhone companion)
//
//  Il "bersaglio" della modalità Sonar sull'iPhone: quale suono localizzare e con
//  quali chiavi filtrarlo. Nasce sul Watch (sul suono appena riconosciuto), viaggia
//  fino all'iPhone via WatchConnectivity, finisce nello `userInfo` della notifica
//  locale e, al tap, apre `PhoneSonarView` già agganciata a questo bersaglio.
//
//  GATING (come sul Watch): un suono di SISTEMA si filtra sugli `identifiers` del
//  modello Apple (es. "door_bell", "doorbell" → CAMPANELLO); un suono PERSONALIZZATO
//  si filtra sulla `customLabel` (la classe grezza del modello custom). Il Watch sa
//  già calcolare gli identifier (`SoundAnalyzerViewModel.identifiers(matching:)`),
//  quindi li manda pronti: l'iPhone non ha bisogno della `soundMap`.
//

import Foundation

/// Descrive il suono da localizzare in modalità Sonar e come riconoscerlo.
struct SonarTarget: Identifiable, Codable, Equatable, Hashable {
    /// Nome leggibile mostrato a schermo (es. "CAMPANELLO").
    var label: String
    /// rawValue di SoundCategory ("emergency" | "danger" | "home" | "attention"):
    /// pilota colore e gravità nella UI.
    var category: String
    /// SF Symbol (se `isSystemIcon`) oppure emoji (altrimenti).
    var iconName: String
    var isSystemIcon: Bool
    /// Identifier del modello di SISTEMA su cui fare gating (vuoto per i suoni custom).
    var identifiers: [String]
    /// Label grezza della classe del modello CUSTOM su cui fare gating (nil per i suoni
    /// di sistema).
    var customLabel: String?

    /// Identità per `.fullScreenCover(item:)`: la label è la chiave logica del suono.
    var id: String { label }

    // MARK: - Serializzazione per WatchConnectivity / notifica

    /// Chiave del tipo di messaggio scambiato col Watch.
    static let messageKind = "sonarHandoff"

    /// Dizionario pronto per `WCSession.sendMessage` / `transferUserInfo` e per lo
    /// `userInfo` della notifica locale. Tipi compatibili con property list.
    var payload: [String: Any] {
        var dict: [String: Any] = [
            "kind": SonarTarget.messageKind,
            "label": label,
            "category": category,
            "iconName": iconName,
            "isSystemIcon": isSystemIcon,
            "identifiers": identifiers
        ]
        if let customLabel { dict["customLabel"] = customLabel }
        return dict
    }

    /// Ricostruisce un `SonarTarget` da un payload ricevuto dal Watch o dallo `userInfo`
    /// di una notifica. Ritorna nil se non è un handoff valido.
    init?(payload: [String: Any]) {
        guard (payload["kind"] as? String) == SonarTarget.messageKind,
              let label = payload["label"] as? String else { return nil }
        self.label = label
        self.category = (payload["category"] as? String) ?? "attention"
        self.iconName = (payload["iconName"] as? String) ?? "waveform"
        self.isSystemIcon = (payload["isSystemIcon"] as? Bool) ?? true
        self.identifiers = (payload["identifiers"] as? [String]) ?? []
        self.customLabel = payload["customLabel"] as? String
    }

    /// Inizializzatore diretto (usato lato Watch per costruire il payload).
    init(label: String, category: String, iconName: String, isSystemIcon: Bool,
         identifiers: [String], customLabel: String?) {
        self.label = label
        self.category = category
        self.iconName = iconName
        self.isSystemIcon = isSystemIcon
        self.identifiers = identifiers
        self.customLabel = customLabel
    }
}
