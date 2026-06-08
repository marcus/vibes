import Foundation

enum PresenceMode: String, Codable, CaseIterable, Identifiable {
  case broadcasting
  case quiet
  case offline

  var id: String { rawValue }

  var label: String {
    switch self {
    case .broadcasting: "Broadcasting"
    case .quiet: "Quiet"
    case .offline: "Offline"
    }
  }
}

enum AgentLabel: String, Codable, CaseIterable, Identifiable {
  case codex
  case claudeCode = "claude_code"
  case gemini
  case grokBuild = "grok_build"
  case cursor
  case aider
  case openCode = "opencode"
  case human
  case unknown

  var id: String { rawValue }

  var label: String {
    switch self {
    case .codex: "Codex"
    case .claudeCode: "Claude Code"
    case .gemini: "Gemini"
    case .grokBuild: "Grok Build"
    case .cursor: "Cursor"
    case .aider: "Aider"
    case .openCode: "OpenCode"
    case .human: "Human"
    case .unknown: "Unknown"
    }
  }
}

struct IdentityConfig: Codable, Equatable {
  var handle: String
  var displayName: String

  enum CodingKeys: String, CodingKey {
    case handle
    case displayName = "display_name"
  }
}

struct DeviceConfig: Codable, Equatable {
  var id: String
  var label: String

  init(id: String = "", label: String) {
    self.id = id
    self.label = label
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Mac"
  }
}

struct ServerConfig: Codable, Equatable {
  var relayURL: URL

  enum CodingKeys: String, CodingKey {
    case relayURL = "relay_url"
  }
}

struct RepoConfig: Codable, Equatable, Identifiable {
  var id: UUID
  var path: String
  var alias: String
  var shareAlias: Bool
  var agent: AgentLabel

  init(id: UUID = UUID(), path: String, alias: String, shareAlias: Bool = false, agent: AgentLabel = .unknown) {
    self.id = id
    self.path = path
    self.alias = alias
    self.shareAlias = shareAlias
    self.agent = agent
  }

  enum CodingKeys: String, CodingKey {
    case id
    case path
    case alias
    case shareAlias = "share_alias"
    case agent
  }
}

struct SharingCardsConfig: Codable, Equatable {
  var gitStats: Bool
  var agentMix: Bool
  var repoAliases: Bool
  var spotify: Bool
  var weather: Bool
  var harness: Bool

  static let defaults = SharingCardsConfig(
    gitStats: true,
    agentMix: true,
    repoAliases: true,
    spotify: false,
    weather: false,
    harness: false
  )

  enum CodingKeys: String, CodingKey {
    case gitStats = "git_stats"
    case agentMix = "agent_mix"
    case repoAliases = "repo_aliases"
    case spotify
    case weather
    case harness
  }
}

struct SharingConfig: Codable, Equatable {
  var cards: SharingCardsConfig

  static let defaults = SharingConfig(cards: .defaults)
}

struct PresenceConfig: Codable, Equatable {
  var mode: PresenceMode
  var manualStatus: String

  static let defaults = PresenceConfig(mode: .broadcasting, manualStatus: "")

  enum CodingKeys: String, CodingKey {
    case mode
    case manualStatus = "manual_status"
  }
}

struct VibesConfig: Codable, Equatable {
  var identity: IdentityConfig
  var device: DeviceConfig
  var server: ServerConfig
  var repos: [RepoConfig]
  var sharing: SharingConfig
  var presence: PresenceConfig

  static func firstLaunch(relayURL: URL, handle: String, displayName: String, deviceLabel: String) -> VibesConfig {
    VibesConfig(
      identity: IdentityConfig(handle: handle, displayName: displayName),
      device: DeviceConfig(id: UUID().uuidString.lowercased(), label: deviceLabel),
      server: ServerConfig(relayURL: relayURL),
      repos: [],
      sharing: .defaults,
      presence: .defaults
    )
  }
}

struct DailyGitStats: Codable, Equatable {
  var commits: Int = 0
  var filesChanged: Int = 0
  var insertions: Int = 0
  var deletions: Int = 0
  var uncommittedInsertions: Int = 0
  var uncommittedDeletions: Int = 0
  var reposTouched: Int = 0
  var latestActivity: Date?
  var repoAliases: [String] = []
  var agentCommitCounts: [String: Int] = [:]

  var hasActivity: Bool {
    commits > 0 || insertions > 0 || deletions > 0 || uncommittedInsertions > 0 || uncommittedDeletions > 0
  }

  var summary: String {
    "\(reposTouched) repos touched - \(commits) commits - +\(insertions) / -\(deletions) LOC"
  }
}

enum JSONValue: Codable, Equatable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      self = .array(try container.decode([JSONValue].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  var intValue: Int? {
    switch self {
    case .int(let value): value
    case .double(let value): Int(value)
    default: nil
    }
  }

  var objectValue: [String: JSONValue]? {
    if case .object(let value) = self { value } else { nil }
  }
}

struct StatusCard: Codable, Equatable, Identifiable {
  var id: String { type }
  var type: String
  var enabled: Bool
  var summary: String?
  var data: [String: JSONValue]
}

struct UserSummary: Codable, Equatable, Identifiable {
  var id: String?
  var handle: String
  var displayName: String

  enum CodingKeys: String, CodingKey {
    case id
    case handle
    case displayName = "display_name"
  }
}

struct RegisterRequest: Codable, Equatable {
  var displayName: String
  var deviceLabel: String

  enum CodingKeys: String, CodingKey {
    case displayName = "display_name"
    case deviceLabel = "device_label"
  }
}

struct RegisteredIdentity: Codable, Equatable {
  var user: UserSummary
  var token: String
}

struct AcceptInviteResult: Codable, Equatable {
  var inviter: UserSummary
  var friend: UserSummary
}

struct PendingInvite: Equatable, Identifiable {
  var code: String

  var id: String { code }
}

struct MergedStatus: Codable, Equatable, Identifiable {
  var id: String { user.handle }
  var user: UserSummary
  var mode: PresenceMode
  var manualStatus: String?
  var derivedStatus: String
  var day: String?
  var updatedAt: Date?
  var cards: [StatusCard]

  enum CodingKeys: String, CodingKey {
    case user
    case mode
    case manualStatus = "manual_status"
    case derivedStatus = "derived_status"
    case day
    case updatedAt = "updated_at"
    case cards
  }
}

struct FeedResponse: Codable, Equatable {
  var you: MergedStatus
  var friends: [MergedStatus]
}

struct InviteSummary: Codable, Equatable, Identifiable {
  var id: String
  var inviteURL: URL?
  var state: String
  var createdAt: Date
  var expiresAt: Date?
  var acceptedBy: String?

  enum CodingKeys: String, CodingKey {
    case id
    case inviteURL = "invite_url"
    case state
    case createdAt = "created_at"
    case expiresAt = "expires_at"
    case acceptedBy = "accepted_by"
  }
}
