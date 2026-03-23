import Foundation

public struct UpdateInfo: Sendable, Equatable {
    public let version: String
    public let releaseURL: URL
    public let releaseNotes: String
}

public final class UpdateChecker: Sendable {
    private let session: any HTTPSession
    private let repoURL: String

    public init(
        session: any HTTPSession = URLSession.shared,
        repoURL: String = "https://api.github.com/repos/nkootstra/claude-usage/releases/latest"
    ) {
        self.session = session
        self.repoURL = repoURL
    }

    /// Check if a newer version is available. Returns nil if up to date or on error.
    public func check(currentVersion: String) async -> UpdateInfo? {
        guard let url = URL(string: repoURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            guard let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String,
                  let releaseURL = URL(string: htmlURL) else { return nil }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let body = json["body"] as? String ?? ""

            guard isNewer(remote: remoteVersion, current: currentVersion) else { return nil }

            return UpdateInfo(version: remoteVersion, releaseURL: releaseURL, releaseNotes: body)
        } catch {
            return nil
        }
    }

    /// Semantic version comparison. Returns true if remote > current.
    private func isNewer(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
