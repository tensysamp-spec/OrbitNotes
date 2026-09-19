import Foundation

enum AppConfig {
    /// ⚠️ CHANGE THIS to your GitHub repo, e.g. "artem/OrbitNotes".
    /// Update checks look at https://github.com/<repo>/releases/latest
    static let githubRepo = "tensysamp-spec/OrbitNotes"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
