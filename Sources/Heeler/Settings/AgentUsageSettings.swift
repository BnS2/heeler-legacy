import Combine
import Foundation

/// Whether the Usage feature is on, for every window and across launches.
/// On by default. `ConsoleStore.setUsageEnabled(_:)` is what turns it off, as
/// it also stops the reads this switch governs.
@MainActor
final class AgentUsageSettings: ObservableObject {
    private static let defaultsKey = "usage.enabled"

    @Published private(set) var isEnabled: Bool
    private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.defaultsKey)
    }
}
