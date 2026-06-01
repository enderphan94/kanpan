import SwiftUI
import AppKit

/// First-launch screen. Asks the user where to keep their vault, or to open an
/// existing one — mirroring the Obsidian "create / open vault" flow.
struct WelcomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var errorText: String?

    private var defaultLocation: URL { Vault.defaultLocation() }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            AppGlyph(size: 78)

            VStack(spacing: 6) {
                Text("Kanpan").font(.system(size: 34, weight: .bold))
                Text("A tidy, markdown-native task board.")
                    .font(.title3).foregroundStyle(.secondary)
            }

            Text("Your tasks live in a **Vault** — a plain folder of `.md` files you fully own. "
                 + "Back it up, sync it with iCloud, or edit it in Obsidian. Nothing is locked away.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                ActionRow(icon: "sparkles", tint: .accentColor,
                          title: "Create New Vault",
                          subtitle: "Start fresh in a folder you choose.") {
                    createVault()
                }
                ActionRow(icon: "folder", tint: .blue,
                          title: "Open Existing Vault",
                          subtitle: "Reload a vault you've used before.") {
                    openVault()
                }
                ActionRow(icon: "bolt.fill", tint: .orange,
                          title: "Use Default Location",
                          subtitle: defaultLocation.path) {
                    store.createVault(at: defaultLocation)
                }
            }
            .frame(maxWidth: 460)

            if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.red)
            }

            Spacer()
            Text("All data is stored locally as Markdown. No account, no cloud, no tracking.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WelcomeBackground())
    }

    private func createVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Create Vault Here"
        panel.message = "Choose (or create) a folder to hold your Kanpan vault."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
        if panel.runModal() == .OK, let url = panel.url {
            store.createVault(at: url)
        }
    }

    private func openVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.message = "Select an existing Kanpan vault folder."
        if panel.runModal() == .OK, let url = panel.url {
            store.openVault(at: url, createDefaultBoardIfEmpty: false)
        }
    }
}

// MARK: - Pieces

/// The app's rounded-square glyph, reused on the welcome screen and elsewhere.
struct AppGlyph: View {
    var size: CGFloat = 64
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.55, blue: 0.98),
                                          Color(red: 0.42, green: 0.40, blue: 0.92)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "checklist")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

private struct ActionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct WelcomeBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.surface, Theme.canvas],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
