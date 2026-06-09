import Foundation

struct GitScanner {
  func scan(repos: [RepoConfig], now: Date = Date()) async -> DailyGitStats {
    var total = DailyGitStats()
    for repo in repos {
      guard FileManager.default.fileExists(atPath: repo.path) else { continue }
      let stats = scanRepo(repo: repo, now: now)
      if stats.hasActivity {
        total.reposTouched += 1
        if repo.shareAlias {
          total.repoAliases.append(repo.alias)
        }
      }
      total.commits += stats.commits
      total.filesChanged += stats.filesChanged
      total.insertions += stats.insertions
      total.deletions += stats.deletions
      total.uncommittedInsertions += stats.uncommittedInsertions
      total.uncommittedDeletions += stats.uncommittedDeletions
      if let activity = stats.latestActivity,
         total.latestActivity == nil || activity > total.latestActivity! {
        total.latestActivity = activity
      }
    }
    total.repoAliases.sort()
    return total
  }

  private func scanRepo(repo: RepoConfig, now: Date) -> DailyGitStats {
    var stats = DailyGitStats()
    guard let authorEmail = configuredUserEmail(repo.path) else {
      scanWorkingTree(repo: repo, into: &stats)
      if stats.hasActivity {
        stats.latestActivity = now
      }
      return stats
    }

    let log = runGit([
      "-C", repo.path,
      "log",
      "--since=midnight",
      "--numstat",
      "--pretty=format:__VIBES_COMMIT__%ae"
    ])
    var includeCurrentCommit = false
    for line in log.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix("__VIBES_COMMIT__") {
        let email = line.replacingOccurrences(of: "__VIBES_COMMIT__", with: "")
        includeCurrentCommit = email.caseInsensitiveCompare(authorEmail) == .orderedSame
        if includeCurrentCommit {
          stats.commits += 1
        }
      } else if includeCurrentCommit {
        parseNumstat(line, committed: true, into: &stats)
      }
    }

    scanWorkingTree(repo: repo, into: &stats)
    if stats.hasActivity {
      stats.latestActivity = now
    }
    return stats
  }

  private func scanWorkingTree(repo: RepoConfig, into stats: inout DailyGitStats) {
    let unstaged = runGit(["-C", repo.path, "diff", "--numstat"])
    for line in unstaged.split(separator: "\n") {
      parseNumstat(line, committed: false, into: &stats)
    }
    let staged = runGit(["-C", repo.path, "diff", "--cached", "--numstat"])
    for line in staged.split(separator: "\n") {
      parseNumstat(line, committed: false, into: &stats)
    }
  }

  private func parseNumstat(_ line: Substring, committed: Bool, into stats: inout DailyGitStats) {
    let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count >= 2 else { return }
    let inserted = Int(parts[0]) ?? 0
    let deleted = Int(parts[1]) ?? 0
    if committed {
      stats.filesChanged += 1
      stats.insertions += inserted
      stats.deletions += deleted
    } else {
      stats.uncommittedInsertions += inserted
      stats.uncommittedDeletions += deleted
    }
  }

  private func runGit(_ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return "" }
      return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    } catch {
      return ""
    }
  }

  private func configuredUserEmail(_ path: String) -> String? {
    let email = runGit(["-C", path, "config", "--get", "user.email"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return email.isEmpty ? nil : email
  }
}

struct StatusPayload: Codable {
  var deviceID: String
  var deviceLabel: String
  var mode: PresenceMode
  var manualStatus: String?
  var derivedStatus: String
  var day: String
  var updatedAt: Date
  var cards: [StatusCard]

  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
    case deviceLabel = "device_label"
    case mode
    case manualStatus = "manual_status"
    case derivedStatus = "derived_status"
    case day
    case updatedAt = "updated_at"
    case cards
  }
}

struct RelayClient {
  var baseURL: URL
  var token: String

  func register(displayName: String, deviceLabel: String) async throws -> RegisteredIdentity {
    try await send(
      path: "/api/register",
      method: "POST",
      body: RegisterRequest(displayName: displayName, deviceLabel: deviceLabel),
      requiresAuth: false
    )
  }

  func publish(_ payload: StatusPayload) async throws {
    let _: PublishResponse = try await send(
      path: "/api/status",
      method: "POST",
      body: payload
    )
  }

  func feed() async throws -> FeedResponse {
    try await send(path: "/api/feed", method: "GET", body: Optional<String>.none)
  }

  func createInvite() async throws -> CreatedInvite {
    try await send(path: "/api/invites", method: "POST", body: EmptyBody())
  }

  func acceptInvite(code: String) async throws -> AcceptInviteResult {
    try await send(
      path: "/api/invites/\(code)/accept",
      method: "POST",
      body: Optional<String>.none
    )
  }

  func listInvites() async throws -> InviteListResponse {
    try await send(path: "/api/invites", method: "GET", body: Optional<String>.none)
  }

  func revokeInvite(id: String) async throws {
    let _: OKResponse = try await send(
      path: "/api/invites/\(id)/revoke",
      method: "POST",
      body: Optional<String>.none
    )
  }

  private func send<Response: Decodable, Body: Encodable>(
    path: String,
    method: String,
    body: Body?,
    requiresAuth: Bool = true
  ) async throws -> Response {
    guard baseURL.isAllowedRelayTransport else {
      throw RelayClientError.insecureRelayURL
    }
    var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
    request.httpMethod = method
    if requiresAuth {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONCoding.encoder.encode(body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw RelayClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      if let error = try? JSONCoding.decoder.decode(ErrorEnvelope.self, from: data) {
        throw RelayClientError.server(error.error.message)
      }
      throw RelayClientError.server("Relay returned HTTP \(http.statusCode).")
    }
    return try JSONCoding.decoder.decode(Response.self, from: data)
  }
}

struct EmptyBody: Codable {}
struct PublishResponse: Codable { var ok: Bool }
struct OKResponse: Codable { var ok: Bool }

struct CreatedInvite: Codable {
  var id: String
  var inviteURL: URL
  var expiresAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case inviteURL = "invite_url"
    case expiresAt = "expires_at"
  }
}

struct InviteListResponse: Codable {
  var invites: [InviteSummary]
}

struct ErrorEnvelope: Codable {
  struct RelayErrorBody: Codable {
    var code: String
    var message: String
  }
  var error: RelayErrorBody
}

enum RelayClientError: LocalizedError {
  case invalidResponse
  case insecureRelayURL
  case server(String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse: "Relay returned an invalid response."
    case .insecureRelayURL: "Relay URL must use HTTPS unless it is localhost."
    case .server(let message): message
    }
  }
}

private extension URL {
  var isAllowedRelayTransport: Bool {
    if scheme == "https" { return true }
    guard scheme == "http", let host = host(percentEncoded: false)?.lowercased() else { return false }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }
}

enum StatusBuilder {
  static func payload(
    config: VibesConfig,
    mode: PresenceMode,
    manualStatus: String,
    stats: DailyGitStats,
    now: Date = Date()
  ) -> StatusPayload {
    let cards = mode == .broadcasting ? buildCards(config: config, stats: stats) : []
    return StatusPayload(
      deviceID: config.device.id,
      deviceLabel: config.device.label,
      mode: mode,
      manualStatus: mode == .broadcasting ? manualStatus.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil,
      derivedStatus: mode == .broadcasting ? deriveVibe(stats: stats) : mode.rawValue,
      day: localDay(now),
      updatedAt: now,
      cards: cards
    )
  }

  private static func buildCards(config: VibesConfig, stats: DailyGitStats) -> [StatusCard] {
    var cards: [StatusCard] = []
    if config.sharing.cards.gitStats {
      cards.append(
        StatusCard(
          type: "git_stats",
          enabled: true,
          summary: stats.summary,
          data: [
            "commits": .int(stats.commits),
            "files_changed": .int(stats.filesChanged),
            "insertions": .int(stats.insertions),
            "deletions": .int(stats.deletions),
            "uncommitted_insertions": .int(stats.uncommittedInsertions),
            "uncommitted_deletions": .int(stats.uncommittedDeletions),
            "repos_touched": .int(stats.reposTouched)
          ]
        )
      )
    }

    if config.sharing.cards.repoAliases && !stats.repoAliases.isEmpty {
      cards.append(
        StatusCard(
          type: "repo_aliases",
          enabled: true,
          summary: stats.repoAliases.joined(separator: ", "),
          data: ["aliases": .array(stats.repoAliases.map { .string($0) })]
        )
      )
    }
    return cards
  }

  static func deriveVibe(stats: DailyGitStats) -> String {
    if stats.commits >= 3 && stats.insertions + stats.deletions > 500 { return "ship mode" }
    if stats.reposTouched >= 4 { return "wandering" }
    if stats.deletions > stats.insertions * 2 && stats.deletions > 100 { return "yak shaving" }
    if stats.commits >= 2 || stats.uncommittedInsertions + stats.uncommittedDeletions > 150 { return "vibing" }
    if stats.hasActivity { return "warming up" }
    return "quiet"
  }

  static func localDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = .current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
