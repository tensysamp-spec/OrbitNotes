import Foundation
import SwiftUI

/// Checks GitHub Releases for a newer version of the app.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release {
        let version: String
        let downloadURL: URL
    }

    /// A newer release, if one was found. Drives the in-app banner.
    @Published var available: Release?
    /// Result of a manual "Check for Updates…" so the UI can show an alert.
    @Published var manualMessage: String?
    @Published var isChecking = false

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

    /// Called at launch. Only hits the network once every 24 hours.
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
            let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
            let download = URL(string: dmg?.browser_download_url ?? release.html_url)!

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
}
