import Foundation

enum PresenceMode: String, Codable, CaseIterable, Identifiable {
  case online
  case offline

  var id: String { rawValue }

  var label: String {
    switch self {
    case .online: "Online"
    case .offline: "Offline"
    }
  }
}

struct IdentityConfig: Codable, Equatable {
  var handle: String
  var displayName: String
  var timezone: String?

  init(handle: String, displayName: String, timezone: String? = nil) {
    self.handle = handle
    self.displayName = displayName
    self.timezone = timezone
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    handle = try container.decode(String.self, forKey: .handle)
    displayName = try container.decode(String.self, forKey: .displayName)
    timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
  }

  enum CodingKeys: String, CodingKey {
    case handle
    case displayName = "display_name"
    case timezone
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

  init(id: UUID = UUID(), path: String, alias: String, shareAlias: Bool = false) {
    self.id = id
    self.path = path
    self.alias = alias
    self.shareAlias = shareAlias
  }

  enum CodingKeys: String, CodingKey {
    case id
    case path
    case alias
    case shareAlias = "share_alias"
  }
}

struct SharingCardsConfig: Codable, Equatable {
  var gitStats: Bool
  var repoAliases: Bool
  var spotify: Bool
  var weather: Bool

  static let defaults = SharingCardsConfig(
    gitStats: true,
    repoAliases: true,
    spotify: false,
    weather: false
  )

  init(
    gitStats: Bool,
    repoAliases: Bool,
    spotify: Bool,
    weather: Bool
  ) {
    self.gitStats = gitStats
    self.repoAliases = repoAliases
    self.spotify = spotify
    self.weather = weather
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    gitStats = try container.decodeIfPresent(Bool.self, forKey: .gitStats) ?? Self.defaults.gitStats
    repoAliases = try container.decodeIfPresent(Bool.self, forKey: .repoAliases) ?? Self.defaults.repoAliases
    spotify = try container.decodeIfPresent(Bool.self, forKey: .spotify) ?? Self.defaults.spotify
    weather = try container.decodeIfPresent(Bool.self, forKey: .weather) ?? Self.defaults.weather
  }

  enum CodingKeys: String, CodingKey {
    case gitStats = "git_stats"
    case repoAliases = "repo_aliases"
    case spotify
    case weather
  }
}

struct SharingRedactionsConfig: Codable, Equatable {
  var repoPaths: Bool
  var branchNames: Bool
  var commitMessages: Bool
  var fileNames: Bool
  var editorActivity: Bool
  var assistantAttribution: Bool

  static let defaults = SharingRedactionsConfig(
    repoPaths: true,
    branchNames: true,
    commitMessages: true,
    fileNames: true,
    editorActivity: true,
    assistantAttribution: true
  )

  init(
    repoPaths: Bool,
    branchNames: Bool,
    commitMessages: Bool,
    fileNames: Bool,
    editorActivity: Bool,
    assistantAttribution: Bool
  ) {
    self.repoPaths = repoPaths
    self.branchNames = branchNames
    self.commitMessages = commitMessages
    self.fileNames = fileNames
    self.editorActivity = editorActivity
    self.assistantAttribution = assistantAttribution
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    repoPaths = try container.decodeIfPresent(Bool.self, forKey: .repoPaths) ?? Self.defaults.repoPaths
    branchNames = try container.decodeIfPresent(Bool.self, forKey: .branchNames) ?? Self.defaults.branchNames
    commitMessages = try container.decodeIfPresent(Bool.self, forKey: .commitMessages) ?? Self.defaults.commitMessages
    fileNames = try container.decodeIfPresent(Bool.self, forKey: .fileNames) ?? Self.defaults.fileNames
    editorActivity = try container.decodeIfPresent(Bool.self, forKey: .editorActivity) ?? Self.defaults.editorActivity
    assistantAttribution = try container.decodeIfPresent(Bool.self, forKey: .assistantAttribution) ?? Self.defaults.assistantAttribution
  }

  enum CodingKeys: String, CodingKey {
    case repoPaths = "repo_paths"
    case branchNames = "branch_names"
    case commitMessages = "commit_messages"
    case fileNames = "file_names"
    case editorActivity = "editor_activity"
    case assistantAttribution = "assistant_attribution"
  }
}

struct SharingConfig: Codable, Equatable {
  var cards: SharingCardsConfig
  var redactions: SharingRedactionsConfig

  static let defaults = SharingConfig(cards: .defaults, redactions: .defaults)

  init(cards: SharingCardsConfig, redactions: SharingRedactionsConfig = .defaults) {
    self.cards = cards
    self.redactions = redactions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cards = try container.decodeIfPresent(SharingCardsConfig.self, forKey: .cards) ?? .defaults
    redactions = try container.decodeIfPresent(SharingRedactionsConfig.self, forKey: .redactions) ?? .defaults
  }

  enum CodingKeys: String, CodingKey {
    case cards
    case redactions
  }
}

struct PresenceConfig: Codable, Equatable {
  var mode: PresenceMode
  var manualStatus: String

  static let defaults = PresenceConfig(mode: .online, manualStatus: "")

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

  static func firstLaunch(
    relayURL: URL,
    handle: String,
    displayName: String,
    deviceLabel: String,
    timezone: String = TimeZone.current.identifier
  ) -> VibesConfig {
    VibesConfig(
      identity: IdentityConfig(handle: handle, displayName: displayName, timezone: timezone),
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
  var timezone: String?
  var avatarUrl: String?

  enum CodingKeys: String, CodingKey {
    case id
    case handle
    case displayName = "display_name"
    case timezone
    case avatarUrl = "avatar_url"
  }
}

// Server-owned art-direction template for AI profile-icon generation, fetched as
// part of `/api/me` (`house_style`). The client composes
// `promptPrefix + userPrompt + promptSuffix`, picks the first `styles` entry that
// the on-device ImageCreator actually offers, and renders a square
// `imageSize`×`imageSize` PNG. Tunable server-side without an app release.
struct HouseStyle: Codable, Equatable {
  var promptPrefix: String
  var promptSuffix: String
  var styles: [String]
  var imageSize: Int

  enum CodingKeys: String, CodingKey {
    case promptPrefix = "prompt_prefix"
    case promptSuffix = "prompt_suffix"
    case styles
    case imageSize = "image_size"
  }
}

struct RegisterRequest: Codable, Equatable {
  var displayName: String
  var deviceLabel: String
  var timezone: String

  enum CodingKeys: String, CodingKey {
    case displayName = "display_name"
    case deviceLabel = "device_label"
    case timezone
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
  var day: String?
  var updatedAt: Date?
  var cards: [StatusCard]

  enum CodingKeys: String, CodingKey {
    case user
    case mode
    case manualStatus = "manual_status"
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
