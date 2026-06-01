import Foundation
import AppKit

/// Self-update against GitHub Releases, modeled on the MarkView updater.
/// Checks `releases/latest`, compares versions, and (when the user agrees)
/// downloads the `.dmg`, mounts it, and spawns a detached shell helper that
/// replaces the running bundle in place and relaunches.
struct UpdateInfo: Equatable {
    let current: String
    let latest: String
    let downloadURL: URL?
    let releaseURL: URL?
    let notes: String

    var isAvailable: Bool {
        downloadURL != nil && Updater.isNewer(latest, than: current)
    }
}

enum UpdaterError: LocalizedError {
    case badResponse
    case notABundle
    case runningFromDMG
    case mountFailed
    case appNotInDMG

    var errorDescription: String? {
        switch self {
        case .badResponse:    return "Couldn't read the latest release from GitHub."
        case .notABundle:     return "Couldn't locate the running app bundle."
        case .runningFromDMG: return "Drag Kanpan into Applications first, then update from the installed copy."
        case .mountFailed:    return "Couldn't mount the downloaded disk image."
        case .appNotInDMG:    return "The downloaded disk image didn't contain Kanpan.app."
        }
    }
}

enum Updater {
    static let repo = "enderphan94/kanpan"

    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    // MARK: Version compare

    /// Normalize "v1.2", "1.2.0" → padded 3-int tuple so a 2-segment tag
    /// compares equal to its 3-segment bundle version.
    static func components(_ s: String) -> [Int] {
        let cleaned = s.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }
        var parts = cleaned.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        return Array(parts.prefix(3))
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = components(latest), c = components(current)
        for i in 0..<3 where l[i] != c[i] { return l[i] > c[i] }
        return false
    }

    // MARK: Check

    static func check() async throws -> UpdateInfo {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Kanpan-Updater/\(current)", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw UpdaterError.badResponse }

        let tag = (json["tag_name"] as? String) ?? ""
        let latest = tag.isEmpty ? current
            : String(tag.drop { $0 == "v" || $0 == "V" })

        var downloadURL: URL?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let name = (asset["name"] as? String)?.lowercased(), name.hasSuffix(".dmg"),
                   let str = asset["browser_download_url"] as? String {
                    downloadURL = URL(string: str); break
                }
            }
        }
        return UpdateInfo(
            current: current,
            latest: latest,
            downloadURL: downloadURL,
            releaseURL: (json["html_url"] as? String).flatMap(URL.init),
            notes: (json["body"] as? String) ?? ""
        )
    }

    // MARK: Apply

    /// Download the `.dmg`, mount it, and spawn the detached helper that swaps
    /// the bundle and relaunches. The caller should terminate the app once this
    /// returns. Runs its blocking work off the main thread.
    static func apply(downloadURL: URL) async throws {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { throw UpdaterError.notABundle }
        guard !bundleURL.path.hasPrefix("/Volumes/") else { throw UpdaterError.runningFromDMG }

        // 1. Download to a temp file.
        let (tmp, _) = try await URLSession.shared.download(from: downloadURL)
        let dmgPath = NSTemporaryDirectory() + "kanpan-update-\(UUID().uuidString).dmg"
        try? FileManager.default.removeItem(atPath: dmgPath)
        try FileManager.default.moveItem(atPath: tmp.path, toPath: dmgPath)

        // 2. Mount it.
        let mountOut = try runProcess("/usr/bin/hdiutil",
                                      ["attach", dmgPath, "-nobrowse", "-readonly"])
        var mountPoint: String?
        for line in mountOut.split(separator: "\n") {
            let cols = line.components(separatedBy: "\t")
            if let last = cols.last?.trimmingCharacters(in: .whitespaces), last.hasPrefix("/Volumes/") {
                mountPoint = last; break
            }
        }
        guard let mount = mountPoint else { throw UpdaterError.mountFailed }
        let srcApp = mount + "/Kanpan.app"
        guard FileManager.default.fileExists(atPath: srcApp) else { throw UpdaterError.appNotInDMG }

        // 3. Write + spawn the detached helper.
        let logDir = NSHomeDirectory() + "/Library/Application Support/Kanpan"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let logFile = logDir + "/update.log"

        let helperPath = NSTemporaryDirectory() + "kanpan-update-\(UUID().uuidString).sh"
        try helperScript.write(toFile: helperPath, atomically: true, encoding: .utf8)
        _ = try? runProcess("/bin/chmod", ["+x", helperPath])

        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [helperPath, pid, srcApp, bundleURL.path, mount, dmgPath, logFile]
        try helper.run()   // detached — survives our termination
    }

    @discardableResult
    private static func runProcess(_ launchPath: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Detached installer: waits for the old process to exit, copies the new
    /// bundle in, strips quarantine, swaps atomically, detaches the DMG, and
    /// relaunches. Logs to ~/Library/Application Support/Kanpan/update.log.
    private static let helperScript = """
    #!/bin/bash
    set -eu
    PARENT_PID="$1"; SRC_APP="$2"; DST_APP="$3"; MOUNT_POINT="$4"; DMG_FILE="$5"; LOG_FILE="$6"
    exec >> "$LOG_FILE" 2>&1
    echo "$(date '+%F %T') update: starting (parent=$PARENT_PID, src=$SRC_APP, dst=$DST_APP)"

    # 1. Wait up to 30s for the old Kanpan to quit.
    for _ in $(seq 1 60); do
        kill -0 "$PARENT_PID" 2>/dev/null || break
        sleep 0.5
    done

    # 2. Stage the new copy beside the old one (same volume → atomic mv).
    DST_DIR="$(dirname "$DST_APP")"
    DST_NAME="$(basename "$DST_APP" .app)"
    STAGE="$DST_DIR/$DST_NAME.new.app"
    BACKUP="$DST_DIR/$DST_NAME.old.app"
    rm -rf "$STAGE" "$BACKUP"
    cp -R "$SRC_APP" "$STAGE"

    # 3. Strip quarantine so Gatekeeper trusts the already-approved app.
    xattr -dr com.apple.quarantine "$STAGE" 2>/dev/null || true

    # 4. Swap.
    [ -e "$DST_APP" ] && mv "$DST_APP" "$BACKUP"
    mv "$STAGE" "$DST_APP"
    ( rm -rf "$BACKUP" ) >/dev/null 2>&1 &

    # 5. Detach + clean up.
    hdiutil detach "$MOUNT_POINT" -quiet || true
    rm -f "$DMG_FILE"

    # 6. Relaunch, then self-delete.
    echo "$(date '+%F %T') launching $DST_APP"
    open -a "$DST_APP"
    rm -f "$0"
    echo "$(date '+%F %T') update: done"
    """
}
