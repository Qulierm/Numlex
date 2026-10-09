import SwiftUI
import NumlexCore

/// A command-routing value published only by the focused main ContentView scene.
/// The binding is the per-window session state, never an AppModel setting.
struct MinimalModeCommandContext {
    var isEnabled: Bool
    var isOn: Binding<Bool>
}

private struct MinimalModeCommandContextKey: FocusedValueKey {
    typealias Value = MinimalModeCommandContext
}

extension FocusedValues {
    var minimalModeCommandContext: MinimalModeCommandContext? {
        get { self[MinimalModeCommandContextKey.self] }
        set { self[MinimalModeCommandContextKey.self] = newValue }
    }
}

struct MinimalModeCommands: Commands {
    @FocusedValue(\.minimalModeCommandContext) private var context
    var language: AppLanguage

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle(L10n.t("minimalMode.menu", language: language),
                   isOn: context?.isOn ?? .constant(false))
                .disabled(context?.isEnabled != true)
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }
}
