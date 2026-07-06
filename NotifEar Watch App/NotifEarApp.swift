
import SwiftUI

@main
struct NotifEar_Watch_AppApp: App {
    @StateObject private var viewModel: SoundAnalyzerViewModel
    @StateObject private var tracker: TrackingService

    init() {
        let vm = SoundAnalyzerViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _tracker = StateObject(wrappedValue: TrackingService(viewModel: vm))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, tracker: tracker)
        }
    }
}
