import SwiftUI

@main
struct KanpanApp: App {
    @StateObject private var store: AppStore

    init() {
        let s = AppStore()
        s.bootstrap()                       // open a saved vault before first paint
        _store = StateObject(wrappedValue: s)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 940, minHeight: 620)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { store.requestNewTask() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!store.hasVault)
                Button("New Board…") { store.requestNewBoard() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!store.hasVault)
            }
            CommandGroup(after: .toolbar) {
                Button("Board View") { store.setViewMode(.board) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Grid View") { store.setViewMode(.grid) }
                    .keyboardShortcut("2", modifiers: .command)
                Divider()
                Button("Reload Vault") { store.reload() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.hasVault {
                MainView()
            } else {
                WelcomeView()
            }
        }
        .preferredColorScheme(store.appearance.colorScheme)
    }
}
