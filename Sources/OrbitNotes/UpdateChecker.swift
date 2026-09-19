import Foundation
import SwiftUI
import AppKit

/// Checks GitHub Releases for a newer version, and can install it in place.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release {
        let version: String
        let downloadURL: URL
    }

    @Published var available: Release?
    @Published var manualMessage: String?
    @Published var isChecking = false
    /// Non-nil while an auto-update is downloading / installing (shown in the banner).
    @Published var installState: String?

    @AppStorage("autoCheckUpdates") var autoCheck = true
    @AppStorage("lastUpdateCheck") private var lastCheck: Double = 0
    @AppStorage("skippedVersion") private var skippedVersion = ""

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let html_url: String
        let assets: [Asset]
    }

    // MARK: - Checking

    func checkIfDue() {
        guard autoCheck, !AppConfig.githubRepo.hasPrefix("YOUR_") else { return }
        let dayAgo = Date().timeIntervalSince1970 - 86_400
        guard lastCheck < dayAgo else { return }
        Task { await check(manual: false) }
    }

    func check(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        if AppConfig.githubRepo.hasPrefix("YOUR_") {
            if manual { manualMessage = "Update checks aren't configured yet. Set AppConfig.githubRepo to your GitHub repository." }
            return
        }

        do {
            let url = URL(string: "https://api.github.com/repos/\(AppConfig.githubRepo)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if manual { manualMessage = "Couldn't reach GitHub to check for updates." }
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            lastCheck = Date().timeIntervalSince1970

            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            guard let dmg = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
                  let download = URL(string: dmg.browser_download_url) else {
                if manual { manualMessage = "The latest release has no .dmg to install." }
                return
            }

            if Self.isVersion(latest, newerThan: AppConfig.version) {
                if manual || latest != skippedVersion {
                    available = Release(version: latest, downloadURL: download)
                }
            } else if manual {
                manualMessage = "You're up to date. Orbit Notes \(AppConfig.version) is the latest version."
            }
        } catch {
            if manual { manualMessage = "Couldn't check for updates: \(error.localizedDescription)" }
        }
    }

    func skip(_ version: String) {
        skippedVersion = version
        available = nil
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Install in place, then relaunch

    func downloadAndInstall(_ release: Release) {
        guard installState == nil else { return }
        installState = "downloading…"
        Task {
            do {
                let (tmp, response) = try await URLSession.shared.download(from: release.downloadURL)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    installState = "download failed (HTTP \(http.statusCode))"; return
                }
                let dmg = URL(fileURLWithPath: NSTemporaryDirectory() + "OrbitNotesUpdate.dmg")
                try? FileManager.default.removeItem(at: dmg)
                try FileManager.default.moveItem(at: tmp, to: dmg)
                installState = "installing…"
                try installFromDMG(dmg)   // launches a helper script and quits the app
            } catch {
                installState = "update failed: \(error.localizedDescription)"
            }
        }
    }

    /// Writes a small shell script that waits for this app to quit, replaces the
    /// app bundle from the DMG, clears quarantine, and relaunches — then quits.
    private func installFromDMG(_ dmg: URL) throws {
        let appPath = Bundle.main.bundlePath
        let appName = (appPath as NSString).lastPathComponent
        let pid = ProcessInfo.processInfo.processIdentifier
        let mount = NSTemporaryDirectory() + "OrbitNotesMount"

        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        rm -rf "\(mount)"
        mkdir -p "\(mount)"
        hdiutil attach "\(dmg.path)" -nobrowse -mountpoint "\(mount)"
        rm -rf "\(appPath)"
        ditto "\(mount)/\(appName)" "\(appPath)"
        hdiutil detach "\(mount)" || true
        xattr -dr com.apple.quarantine "\(appPath)" || true
        open "\(appPath)"
        """

        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory() + "orbit_update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "nohup /bin/bash \"\(scriptURL.path)\" >/dev/null 2>&1 &"]
        try task.run()

        NSApp.terminate(nil)
    }
}
