import SwiftUI

@main
struct MaybePlaygroundApp: App {
    // Production follows the system; the UI suite can launch either appearance.
    private var testAppearance: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-dark") { return .dark }
        #endif
        return nil
    }

    var body: some Scene {
        WindowGroup {
            PlaygroundView()
                .preferredColorScheme(testAppearance)
        }
    }
}
