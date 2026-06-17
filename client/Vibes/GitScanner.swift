import CryptoKit
import Foundation

// `nonisolated` so the scan never runs on the main actor. The project builds
// with default main-actor isolation (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor),
// which would otherwise pin these synchronous, blocking git calls to the main
// thread and freeze the UI on a slow or large repo.
nonisolated struct GitScanner {
  func scan(repos: [RepoConfig], dayWindow: VibesDayWindow, now: Date = Date()) async -> DailyGitStats {
    var total = DailyGitStats()
    var seenCommits = Set<String>()
    for repo in repos {
      guard FileManager.default.fileExists(atPath: repo.path) else { continue }
      let stats = scanRepo(repo: repo, dayWindow: dayWindow, now: now)
      if stats.hasActivity {
        total.reposTouched += 1
        if repo.shareAlias {
          total.repoAliases.append(repo.alias)
        }
      }
      for commit in stats.commitDetails where !seenCommits.contains(commit.id) {
        seenCommits.insert(commit.id)
        total.commitDetails.append(commit)
        total.commits += 1
        total.filesChanged += commit.filesChanged
        total.insertions += commit.insertions
        total.deletions += commit.deletions
        if total.latestActivity == nil || commit.committedAt > total.latestActivity! {
          total.latestActivity = commit.committedAt
        }
      }
    }
    total.repoAliases.sort()
    return total
  }

  // Only committed work counts: commits authored by the repo's configured user
  // email inside the day window. Uncommitted (staged/unstaged) diffs are ignored
  // — they carry no timestamp, so a stale dirty file would otherwise mark the
  // repo "worked on today" every day until committed or reverted.
  private func scanRepo(repo: RepoConfig, dayWindow: VibesDayWindow, now: Date) -> DailyGitStats {
    var stats = DailyGitStats()
    guard let authorEmail = configuredUserEmail(repo.path) else {
      return stats
    }

    let log = runGit([
      "-C", repo.path,
      "log",
      "--branches",
      "--since=\(DateFormatters.isoWithFractional.string(from: dayWindow.startAt))",
      "--until=\(DateFormatters.isoWithFractional.string(from: min(now, dayWindow.endAt)))",
      "--numstat",
      "--pretty=format:__VIBES_COMMIT__%H%x09%ae%x09%cI"
    ])
    var includeCurrentCommit = false
    var currentCommit: GitCommitStats?

    func finishCurrentCommit() {
      guard includeCurrentCommit, let commit = currentCommit else { return }
      stats.commitDetails.append(commit)
      stats.commits += 1
      stats.filesChanged += commit.filesChanged
      stats.insertions += commit.insertions
      stats.deletions += commit.deletions
      if stats.latestActivity == nil || commit.committedAt > stats.latestActivity! {
        stats.latestActivity = commit.committedAt
      }
    }

    for line in log.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix("__VIBES_COMMIT__") {
        finishCurrentCommit()
        let fields = line
          .replacingOccurrences(of: "__VIBES_COMMIT__", with: "")
          .split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3 else {
          includeCurrentCommit = false
          currentCommit = nil
          continue
        }
        let email = String(fields[1])
        includeCurrentCommit = email.caseInsensitiveCompare(authorEmail) == .orderedSame
        currentCommit = includeCurrentCommit
          ? GitCommitStats(
            id: Self.commitFingerprint(String(fields[0])),
            committedAt: DateFormatters.iso.date(from: String(fields[2]))
              ?? DateFormatters.isoWithFractional.date(from: String(fields[2]))
              ?? now
          )
          : nil
      } else if includeCurrentCommit {
        parseNumstat(line, into: &currentCommit)
      }
    }
    finishCurrentCommit()

    return stats
  }

  private func parseNumstat(_ line: Substring, into commit: inout GitCommitStats?) {
    let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count >= 2 else { return }
    commit?.filesChanged += 1
    commit?.insertions += Int(parts[0]) ?? 0
    commit?.deletions += Int(parts[1]) ?? 0
  }

  private static func commitFingerprint(_ rawHash: String) -> String {
    let namespaced = "vibes.git.commit.v1:\(rawHash.lowercased())"
    let digest = SHA256.hash(data: Data(namespaced.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  // Hard ceiling on any single git invocation. A repo that hangs (filesystem
  // stall, lock contention, pathological history) must not wedge the scan
  // forever — past this, the process is killed and the call returns "".
  private static let gitTimeout: TimeInterval = 20

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
    } catch {
      return ""
    }

    // Drain BOTH pipes concurrently. macOS pipe buffers are ~64KB: if we waited
    // for the process to exit before reading (or read one pipe while the other
    // filled), a chatty `git log --numstat` on a large repo would block git's
    // write() while we block on waitUntilExit() — a permanent deadlock.
    let outputQueue = DispatchQueue(label: "vibes.git.stdout")
    let errorQueue = DispatchQueue(label: "vibes.git.stderr")
    var outputData = Data()
    let outputGroup = DispatchGroup()
    outputQueue.async(group: outputGroup) {
      outputData = output.fileHandleForReading.readDataToEndOfFile()
    }
    errorQueue.async(group: outputGroup) {
      _ = error.fileHandleForReading.readDataToEndOfFile()
    }

    // Wait for exit with a timeout; kill the process if it overruns so the
    // pipe readers above can hit EOF and the group can complete.
    let waiter = DispatchGroup()
    waiter.enter()
    DispatchQueue(label: "vibes.git.wait").async {
      process.waitUntilExit()
      waiter.leave()
    }
    let exited = waiter.wait(timeout: .now() + Self.gitTimeout) == .success
    if !exited {
      process.terminate()
      process.waitUntilExit()
    }
    outputGroup.wait()

    guard exited, process.terminationStatus == 0 else { return "" }
    return String(data: outputData, encoding: .utf8) ?? ""
  }

  private func configuredUserEmail(_ path: String) -> String? {
    let email = runGit(["-C", path, "config", "--get", "user.email"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return email.isEmpty ? nil : email
  }
}

nonisolated struct VibesDayWindow: Equatable {
  var day: String
  var timezone: String
  var startAt: Date
  var endAt: Date

  static func current(now: Date = Date(), timezone identifier: String) -> VibesDayWindow {
    let timezone = TimeZone(identifier: identifier) ?? .current
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    let start = calendar.startOfDay(for: now)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)

    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = timezone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"

    return VibesDayWindow(
      day: formatter.string(from: now),
      timezone: timezone.identifier,
      startAt: start,
      endAt: end
    )
  }
}

struct StatusPayload: Codable {
  var deviceID: String
  var deviceLabel: String
  var mode: PresenceMode
  var manualStatus: String?
  var day: String
  var dayTimezone: String
  var dayStartAt: Date
  var dayEndAt: Date
  var updatedAt: Date
  var cards: [StatusCard]

  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
    case deviceLabel = "device_label"
    case mode
    case manualStatus = "manual_status"
    case day
    case dayTimezone = "day_timezone"
    case dayStartAt = "day_start_at"
    case dayEndAt = "day_end_at"
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
      body: RegisterRequest(
        displayName: displayName,
        deviceLabel: deviceLabel,
        timezone: TimeZone.current.identifier
      ),
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

  func me() async throws -> AccountResponse {
    try await send(path: "/api/me", method: "GET", body: Optional<String>.none)
  }

  // Upload a freshly generated PNG as the current profile icon. The body is raw
  // image bytes (not JSON), so this can't use the generic `send<>`; the short
  // prompt/style ride along as headers since the body is binary.
  func uploadAvatar(pngData: Data, prompt: String, style: String) async throws -> AvatarUploadResult {
    try await sendRaw(
      path: "/api/avatar",
      method: "POST",
      body: pngData,
      contentType: "image/png",
      headers: [
        "X-Avatar-Prompt": prompt,
        "X-Avatar-Style": style
      ]
    )
  }

  // Set a two-color gradient profile icon (rendered client-side; no PNG upload).
  // PUTs JSON `{ start, end }` as "#RRGGBB" hex; the server validates, stores, and
  // returns the updated avatar fields. Reuses the JSON `send<>` (it already takes
  // an arbitrary method).
  func setAvatarGradient(start: String, end: String) async throws -> AvatarGradientResult {
    try await send(
      path: "/api/avatar/gradient",
      method: "PUT",
      body: AvatarGradientRequest(start: start, end: end)
    )
  }

  // Clear the current profile icon, reverting to initials.
  func deleteAvatar() async throws {
    let _: OKResponse = try await send(
      path: "/api/avatar",
      method: "DELETE",
      body: Optional<String>.none
    )
  }

  func createInvite() async throws -> CreatedInvite {
    try await send(path: "/api/invites", method: "POST", body: EmptyBody())
  }

  // Who created an invite code — powers the sheet's "<name> invited you".
  // Unauthenticated by design: holding the code is the capability.
  func inviteLookup(code: String) async throws -> InviteLookup {
    let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
    return try await send(
      path: "/api/invites/\(encoded)",
      method: "GET",
      body: Optional<String>.none,
      requiresAuth: false
    )
  }

  // Mint a pairing code for adding another Mac to this account.
  func createDeviceLinkCode() async throws -> DeviceLinkCode {
    try await send(path: "/api/devices/link-codes", method: "POST", body: EmptyBody())
  }

  // Exchange a pairing code (typed on the new Mac) for a fresh per-device
  // token plus account info — the same response shape as register, so the
  // setup flow is shared.
  func claimDeviceLinkCode(code: String, deviceLabel: String) async throws -> RegisteredIdentity {
    try await send(
      path: "/api/devices/link-codes/claim",
      method: "POST",
      body: ClaimLinkCodeRequest(code: code, deviceLabel: deviceLabel),
      requiresAuth: false
    )
  }

  // The account's active devices (labeled tokens), with the caller flagged.
  func listDevices() async throws -> DeviceListResponse {
    try await send(path: "/api/devices", method: "GET", body: Optional<String>.none)
  }

  // Mint a fresh labeled token using this client's (already trusted) token —
  // the iCloud-Keychain welcome-back path, so the synced credential never
  // becomes the new Mac's working token.
  func mintDeviceToken(label: String) async throws -> RegisteredIdentity {
    try await send(path: "/api/tokens", method: "POST", body: MintTokenRequest(label: label))
  }

  func revokeToken(id: String) async throws {
    let _: OKResponse = try await send(
      path: "/api/tokens/revoke",
      method: "POST",
      body: RevokeTokenRequest(tokenId: id)
    )
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
        throw RelayClientError.serverResponse(
          message: error.error.message,
          status: http.statusCode,
          code: error.error.code
        )
      }
      throw RelayClientError.serverResponse(
        message: "Relay returned HTTP \(http.statusCode).",
        status: http.statusCode,
        code: nil
      )
    }
    return try JSONCoding.decoder.decode(Response.self, from: data)
  }

  // Sibling of `send<>` for raw-byte request bodies (the generic one is JSON
  // only). Same HTTPS guard, bearer auth, and error-envelope decoding; the body
  // is posted verbatim with the given content type. Header values are sanitized
  // to a header-safe ASCII subset so a stray newline/control char can't break
  // the request.
  private func sendRaw<Response: Decodable>(
    path: String,
    method: String,
    body: Data,
    contentType: String,
    headers: [String: String] = [:]
  ) async throws -> Response {
    guard baseURL.isAllowedRelayTransport else {
      throw RelayClientError.insecureRelayURL
    }
    var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    for (name, value) in headers {
      request.setValue(value.headerSafe, forHTTPHeaderField: name)
    }
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw RelayClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      if let error = try? JSONCoding.decoder.decode(ErrorEnvelope.self, from: data) {
        throw RelayClientError.serverResponse(
          message: error.error.message,
          status: http.statusCode,
          code: error.error.code
        )
      }
      throw RelayClientError.serverResponse(
        message: "Relay returned HTTP \(http.statusCode).",
        status: http.statusCode,
        code: nil
      )
    }
    return try JSONCoding.decoder.decode(Response.self, from: data)
  }
}

struct EmptyBody: Codable {}
struct PublishResponse: Codable { var ok: Bool }
struct OKResponse: Codable { var ok: Bool }

struct AccountResponse: Codable {
  var user: UserSummary
  var houseStyle: HouseStyle?

  enum CodingKeys: String, CodingKey {
    case user
    case houseStyle = "house_style"
  }
}

struct AvatarUploadResult: Codable {
  var id: String
  var avatarURL: String

  enum CodingKeys: String, CodingKey {
    case id
    case avatarURL = "avatar_url"
  }
}

struct AvatarGradientRequest: Codable {
  var start: String
  var end: String
}

// The updated avatar fields the server echoes back after setting a gradient.
// Decoded loosely (all optional) so future field additions don't break decoding.
struct AvatarGradientResult: Codable {
  var avatarKind: String?
  var avatarGradient: AvatarGradient?
  var avatarURL: String?

  enum CodingKeys: String, CodingKey {
    case avatarKind = "avatar_kind"
    case avatarGradient = "avatar_gradient"
    case avatarURL = "avatar_url"
  }
}

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
  case serverResponse(message: String, status: Int, code: String?)

  var errorDescription: String? {
    switch self {
    case .invalidResponse: "Relay returned an invalid response."
    case .insecureRelayURL: "Relay URL must use HTTPS unless it is localhost."
    case .serverResponse(let message, _, _): message
    }
  }

  var statusCode: Int? {
    switch self {
    case .serverResponse(_, let status, _): status
    default: nil
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
    now: Date = Date(),
    dayWindow: VibesDayWindow? = nil,
    extraCards: [StatusCard] = []
  ) -> StatusPayload {
    let window = dayWindow ?? VibesDayWindow.current(
      now: now,
      timezone: config.identity.timezone ?? TimeZone.current.identifier
    )
    return StatusPayload(
      deviceID: config.device.id,
      deviceLabel: config.device.label,
      mode: mode,
      manualStatus: manualStatus.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
      day: window.day,
      dayTimezone: window.timezone,
      dayStartAt: window.startAt,
      dayEndAt: window.endAt,
      updatedAt: now,
      // Provider-built cards (music, weather) ride along after the git cards;
      // AppModel gates them on the sharing toggles before they get here.
      cards: buildCards(stats: stats, sharing: config.sharing.cards) + extraCards
    )
  }

  private static func buildCards(stats: DailyGitStats, sharing: SharingCardsConfig) -> [StatusCard] {
    var cards: [StatusCard] = []
    if sharing.gitStats {
      var gitData: [String: JSONValue] = [
        "commits": .int(stats.commits),
        "files_changed": .int(stats.filesChanged),
        "insertions": .int(stats.insertions),
        "deletions": .int(stats.deletions),
        "repos_touched": .int(stats.reposTouched)
      ]
      if !stats.commitDetails.isEmpty {
        gitData["commit_details"] = .array(stats.commitDetails.map { commit in
          .object([
            "id": .string(commit.id),
            "committed_at": .string(DateFormatters.isoWithFractional.string(from: commit.committedAt)),
            "files_changed": .int(commit.filesChanged),
            "insertions": .int(commit.insertions),
            "deletions": .int(commit.deletions)
          ])
        })
      }
      cards.append(
        StatusCard(
          type: "git_stats",
          enabled: true,
          summary: stats.summary,
          data: gitData
        )
      )
    }

    if sharing.repoAliases, !stats.repoAliases.isEmpty {
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

  static func vibesDay(_ date: Date, timezone: String) -> String {
    VibesDayWindow.current(now: date, timezone: timezone).day
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }

  // Strip control characters (newlines, CR, etc.) so a user-typed prompt can be
  // safely passed as an HTTP header value.
  var headerSafe: String {
    unicodeScalars.filter { $0 >= " " && $0 != "\u{7F}" }
      .map(String.init)
      .joined()
  }
}
