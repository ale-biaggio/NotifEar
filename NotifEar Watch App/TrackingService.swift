//
//  TrackingService.swift
//  NotifEar Watch App
//
//  Modalità Tracking: avviata ad app aperta toccando il tile di un suono riconosciuto.
//
//  COME FUNZIONA LA VIBRAZIONE (modello "forza per fascia")
//  Non esistono più firme aptiche fisse per ogni suono. La vibrazione segue l'intensità
//  del suono riconosciuto, letta istante per istante: a cadenza FISSA (`hapticPeriod`)
//  il motore emette, ad ogni "lettura", il preset haptic della fascia di volume corrente
//  (`hapticLadder`, dal più leggero `.click` al più forte `.failure`). Suono debole →
//  colpo leggero; suono forte → colpo pieno; sotto una soglia minima → silenzio. A
//  variare col volume è SOLO la forza del preset, non la frequenza né il numero di colpi.
//
//  PERCHÉ I PRESET COME GRADINI DI FORZA
//  Su watchOS non esiste un controllo di ampiezza haptic indipendente (CoreHaptics non è
//  disponibile): l'unica via per "più o meno intenso" è scegliere fra i preset
//  `WKHapticType` quelli via via più forti. Non conta che differiscano anche per durata o
//  numero di battiti (uno/due/tre): conta la forza percepita crescente.
//
//  ARCHITETTURA
//   - `monitorTimer`: loop a 10 Hz che aggiorna `smoothedConfidence` (envelope follower
//     sul classificatore, per il gating del target) e `liveLevel` (intensità 0...1 del
//     volume corrente, 0 quando il target non è presente). È la sorgente che il motore
//     aptico legge.
//   - `runTrackingHaptics(generation:)`: loop ricorsivo via `asyncAfter` a cadenza fissa
//     `hapticPeriod`. Ad ogni giro legge `liveLevel` ed emette il preset della fascia
//     corrispondente (niente vibrazione sotto `silenceThreshold`). Il `generation`
//     counter invalida le closure pending quando il tracking viene fermato o riavviato
//     (cancellation safety).
//

import Foundation
import SwiftUI
import Combine
import WatchKit

final class TrackingService: ObservableObject {

    // MARK: - Stato esposto

    enum State: Equatable {
        case idle
        case tracking(target: SoundInfo)
    }

    @Published var state: State = .idle

    /// Intensità 0...1 dell'ultimo campione di volume (con il target presente).
    /// Pilota la barra, lo sfondo e la scala dell'emoji nella UI, ED È la sorgente che
    /// il motore aptico legge per decidere quanto fitti emettere i colpetti. Aggiornato
    /// dal `monitorTimer` a 10 Hz; 0 quando il target non è presente.
    @Published var liveLevel: Float = 0

    /// Contatore monotono incrementato ad ogni colpetto effettivamente lanciato.
    /// La UI ascolta `.onChange` per spawnare un cerchio concentrico in sincrono
    /// con la vibrazione — feedback visivo ridondante, indispensabile sul simulatore
    /// dove l'haptic è no-op.
    @Published var pulseCounter: UInt32 = 0

    // MARK: - Config — scala dB per l'intensità del suono

    /// RMS di riferimento (~0 dB sull'asse interno). A questo livello l'intensità
    /// satura a 1.0. Tarato sul range osservato col test all'altoparlante (29/05/2026):
    /// volume "alto" letto ≈ 0.0150 → deve corrispondere al 100%. Se in uso reale i suoni
    /// risultano più forti di così e saturano subito, alzare questo valore.
    private static let rmsReference: Float = 0.015
    /// Pavimento della scala dB. Tarato perché il volume "basso" osservato (RMS ≈ 0.0010)
    /// cada vicino allo 0% senza azzerarsi: −28 dB sotto il riferimento ≈ rapporto 0.04×,
    /// cioè RMS ≈ 0.0006 → 0%.
    private static let dBFloor: Float = -28
    /// Soffitto della scala dB.
    private static let dBCeiling: Float = 0

    // MARK: - Config — preset haptic per fascia di intensità

    /// Cadenza FISSA con cui il motore emette una vibrazione (una "lettura" del volume).
    /// A cambiare col volume è la FORZA del preset scelto, NON la frequenza: i colpi
    /// arrivano sempre a questo ritmo costante. ~0,45 s: colpi distinti, reazione rapida,
    /// e tempo sufficiente perché anche i preset più lunghi (`.failure`) suonino interi.
    private static let hapticPeriod: TimeInterval = 0.45

    /// Sotto questa intensità il suono è troppo debole → nessuna vibrazione.
    private static let silenceThreshold: Float = 0.06

    /// Scala dei preset haptic dal più LEGGERO al più FORTE. L'intensità del suono sceglie
    /// quale emettere: più forte il suono, più "pieno" il colpo. Su watchOS l'ampiezza non
    /// è modulabile in continuo, quindi si usano i preset come gradini di forza — non conta
    /// quanti battiti abbia ciascuno (uno, due, tre), conta la forza percepita crescente.
    /// Ordine facilmente tarabile: per più o meno fasce, aggiungere/togliere voci.
    private static let hapticLadder: [WKHapticType] = [.click, .start, .notification, .failure]

    /// Sceglie il preset in base all'intensità (0...1) dividendo il range in fasce uguali
    /// (con `hapticLadder` a 4 voci: <0,25 → `.click`, <0,5 → `.start`, <0,75 →
    /// `.notification`, oltre → `.failure`). Restituisce nil sotto `silenceThreshold`.
    private static func haptic(forIntensity intensity: Float) -> WKHapticType? {
        guard intensity >= silenceThreshold else { return nil }
        let clamped = min(max(intensity, 0), 1)
        let count = hapticLadder.count
        let index = min(Int(clamped * Float(count)), count - 1)
        return hapticLadder[index]
    }

    // MARK: - Config — gating sul suono target

    /// Sotto questa confidence smoothed consideriamo il target non più presente →
    /// niente vibrazione.
    private static let confidenceThreshold: Float = 0.4
    /// Memoria della confidence smoothed (envelope follower). 0.96 applicato a 10 Hz
    /// → mezza-vita di ~1.7 s. Evita che le valli interne di una sirena pulsante
    /// facciano flippare il gate aperto/chiuso ad ogni ciclo della sirena.
    private static let confidenceDecay: Float = 0.96

    /// Periodo del monitor (UI + gating). 10 Hz: ridipinge la barra in modo fluido
    /// e rileva la sparizione del target entro 100 ms.
    private static let monitorPeriod: TimeInterval = 0.1

    // MARK: - Dipendenze

    private weak var viewModel: SoundAnalyzerViewModel?

    // MARK: - Stato interno

    private var monitorTimer: Timer?
    /// Confidence smoothed con envelope follower, aggiornata dal `monitorTimer`.
    private var smoothedConfidence: Float = 0
    /// Counter che invalida le closure pending del loop aptico su stop/restart.
    private var executionGeneration: UInt64 = 0

    // MARK: - Stato debug (schermata "Pattern debug")

    /// True quando il motore sta girando in modalità debug (innescato dalla schermata
    /// di test). Bypassa il gating del classificatore e usa `debugIntensity` come volume
    /// fittizio, così l'utente può provare le varie intensità senza una sorgente reale.
    /// Il debug NON si ferma da solo: gira finché non si preme Stop, si cambia livello
    /// o si lascia la tab.
    private var isDebugPlayback: Bool = false
    /// Intensità (0...1) usata dal debug al posto del volume reale del microfono. La
    /// schermata di test la imposta tramite `playDebugPattern(for:intensity:)` per far
    /// provare le varie densità di colpetti. Default 0.5.
    private var debugIntensity: Float = 0.5

    // MARK: - Init

    init(viewModel: SoundAnalyzerViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - API

    /// Avvia la modalità Tracking sul `target` dato: arma il classificatore sul suono,
    /// avvia il monitor UI/gating e fa partire il loop aptico che segue l'intensità.
    func startTracking(target: SoundInfo) {
        guard let vm = viewModel else { return }
        if case .tracking(let current) = state, current == target { return }

        // Se era in corso un debug playback, lo interrompiamo.
        isDebugPlayback = false

        vm.setTrackingTarget(for: target)

        smoothedConfidence = 0
        liveLevel = 0
        pulseCounter = 0

        state = .tracking(target: target)
        WKInterfaceDevice.current().play(.start)

        executionGeneration &+= 1
        let myGen = executionGeneration

        startMonitorLoop()
        DispatchQueue.main.async { [weak self] in
            self?.runTrackingHaptics(generation: myGen)
        }
    }

    /// Termina la modalità Tracking. Le closure pending del loop aptico si
    /// auto-invalidano via `executionGeneration`.
    func stopTracking() {
        viewModel?.clearTrackingTarget()
        executionGeneration &+= 1
        stopMonitorLoop()
        state = .idle
        liveLevel = 0
        smoothedConfidence = 0
    }

    // MARK: - API debug (schermata "Pattern debug" — RIMUOVERE PRIMA DEL RILASCIO)

    /// Avvia il motore aptico in modalità debug, **bypassando** il classificatore, a un
    /// volume fittizio fisso (`intensity`, 0...1). Usata dalla schermata di test per far
    /// provare all'utente le varie densità di colpetti senza dover riprodurre il suono
    /// reale: debole = colpetti radi, forte = raffica fitta. Il parametro `label` serve
    /// solo alla view per evidenziare il tile attivo (non cambia più la vibrazione: tutti
    /// i suoni seguono la stessa logica intensità→densità). Il loop NON si ferma da solo:
    /// continua finché non si chiama `stopDebugPattern()`.
    func playDebugPattern(for label: String, intensity: Float = 0.5) {
        debugIntensity = intensity
        // Interrompe qualunque cosa fosse in corso (tracking normale o un altro debug).
        viewModel?.clearTrackingTarget()
        stopMonitorLoop()

        executionGeneration &+= 1
        let myGen = executionGeneration

        isDebugPlayback = true
        state = .idle

        DispatchQueue.main.async { [weak self] in
            self?.runDebugHaptics(generation: myGen)
        }
    }

    /// Ferma il debug playback. Le closure pending del loop si auto-invalidano via
    /// `executionGeneration`.
    func stopDebugPattern() {
        isDebugPlayback = false
        executionGeneration &+= 1
    }

    /// True se il motore è attualmente in playback debug. La debug view legge questa
    /// proprietà per evidenziare il tile attivo.
    var isPlayingDebugPattern: Bool { isDebugPlayback }

    // MARK: - Monitor loop (UI + gating)

    private func startMonitorLoop() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: Self.monitorPeriod, repeats: true) { [weak self] _ in
            self?.monitorTick()
        }
    }

    private func stopMonitorLoop() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    /// Aggiorna l'envelope follower sulla confidence e ricalcola `liveLevel` (intensità
    /// corrente del volume, 0 se il target non è presente). Non emette colpetti: quelli
    /// li gestisce il loop aptico, che legge `liveLevel`.
    private func monitorTick() {
        guard case .tracking = state, let vm = viewModel else { return }

        smoothedConfidence = max(vm.currentTargetConfidence, smoothedConfidence * Self.confidenceDecay)
        let isPresent = smoothedConfidence >= Self.confidenceThreshold

        liveLevel = isPresent ? Self.intensity(forRMS: vm.currentRMS) : 0
    }

    // MARK: - Loop aptico (ricorsivo)

    /// Loop in modalità Tracking: a cadenza FISSA (`hapticPeriod`) legge `liveLevel`
    /// (intensità istantanea del suono) ed emette il preset haptic della fascia
    /// corrispondente — più forte il suono, più forte il colpo. La frequenza non cambia
    /// mai: a variare è solo la forza del preset.
    private func runTrackingHaptics(generation: UInt64) {
        guard case .tracking = state, generation == executionGeneration else { return }

        emitHaptic(forLevel: liveLevel)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hapticPeriod) { [weak self] in
            self?.runTrackingHaptics(generation: generation)
        }
    }

    /// Come `runTrackingHaptics` ma in modalità debug: nessun gating sul classificatore,
    /// usa il volume fittizio `debugIntensity` al posto di `liveLevel`. Si auto-ferma
    /// quando `isDebugPlayback` torna false.
    private func runDebugHaptics(generation: UInt64) {
        guard isDebugPlayback, generation == executionGeneration else { return }

        emitHaptic(forLevel: debugIntensity)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hapticPeriod) { [weak self] in
            self?.runDebugHaptics(generation: generation)
        }
    }

    /// Emette il preset haptic della fascia di `level` (più forte il suono, più forte il
    /// colpo). Sotto `silenceThreshold` non vibra. Incrementa `pulseCounter` per la UI
    /// (un cerchio concentrico per colpo) solo quando vibra davvero. Condiviso da
    /// tracking e debug.
    private func emitHaptic(forLevel level: Float) {
        guard let type = Self.haptic(forIntensity: level) else { return }
        WKInterfaceDevice.current().play(type)
        pulseCounter &+= 1
    }

    // MARK: - Mapping volume → intensità → colpo

    /// Converte un RMS audio in intensità normalizzata 0...1 sulla scala dB.
    private static func intensity(forRMS rms: Float) -> Float {
        let safe = max(rms, 1e-5)  // evita log(0)
        let db = 20 * log10f(safe / rmsReference)
        let normalized = (db - dBFloor) / (dBCeiling - dBFloor)
        return min(max(normalized, 0), 1)
    }

    // MARK: - Cleanup

    deinit {
        executionGeneration &+= 1
        monitorTimer?.invalidate()
    }
}
