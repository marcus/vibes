import Foundation
import Security
import UniformTypeIdentifiers

struct ConfigStore {
  let configURL: URL

  init() {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    configURL = base.appendingPathComponent("Vibes", isDirectory: true).appendingPathComponent("config.json")
  }

  // Escape hatch for exercising load/save/backup against a scratch directory.
  init(configURL: URL) {
    self.configURL = configURL
  }

  func load() throws -> VibesConfig? {
    guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
    let data = try Data(contentsOf: configURL)
    do {
      return try JSONCoding.decoder.decode(VibesConfig.self, from: data)
    } catch {
      // A bare DecodingError.localizedDescription is "The data couldn't be read
      // because it is missing." — true and useless. Name the file and the key.
      throw ConfigStoreError.unreadable(url: configURL, underlying: error)
    }
  }

  func save(_ config: VibesConfig) throws {
    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    // An unreadable config still holds the user's repos and sharing settings.
    // Setting up again would overwrite it with first-launch defaults, so keep a
    // copy first: an old binary or a truncated write becomes recoverable
    // instead of silent data loss.
    backupUnreadableConfig()
    let data = try JSONCoding.encoder.encode(config)
    try data.write(to: configURL, options: [.atomic])
  }

  // Returns the backup path when one was made. Best-effort by contract: a
  // failure here must not block the user from finishing setup.
  @discardableResult
  func backupUnreadableConfig() -> URL? {
    guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
    guard (try? load()) == nil else { return nil }
    let base = configURL.deletingLastPathComponent()
    for index in 1...99 {
      let candidate = base.appendingPathComponent("config.json.bak-\(index)")
      guard !FileManager.default.fileExists(atPath: candidate.path) else { continue }
      guard (try? FileManager.default.moveItem(at: configURL, to: candidate)) != nil else { return nil }
      return candidate
    }
    return nil
  }

  func importConfig(from url: URL) throws -> ImportedConfig {
    let data = try Data(contentsOf: url)
    let imported = try JSONCoding.decoder.decode(ImportedConfig.self, from: data)
    var config = imported.config
    if config.device.id.isEmpty {
      config.device.id = UUID().uuidString.lowercased()
    }
    if config.device.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      config.device.label = Host.current().localizedName ?? "Mac"
    }
    return ImportedConfig(config: config, token: imported.token)
  }
}

// Config on disk exists but won't decode — usually an older Vibes binary
// reading a newer config, or a partial write. Distinct from "no config yet" so
// the UI can say so instead of looking like a fresh install.
enum ConfigStoreError: LocalizedError {
  case unreadable(url: URL, underlying: Error)

  var errorDescription: String? {
    switch self {
    case let .unreadable(url, underlying):
      "Couldn't read config at \(url.path): \(Self.detail(underlying))"
    }
  }

  private static func detail(_ error: Error) -> String {
    guard let decoding = error as? DecodingError else { return error.localizedDescription }
    switch decoding {
    case let .keyNotFound(key, context):
      return "missing key \"\(key.stringValue)\"\(Self.at(context))"
    case let .valueNotFound(_, context):
      return "null value\(Self.at(context))"
    case let .typeMismatch(type, context):
      return "expected \(type)\(Self.at(context))"
    case let .dataCorrupted(context):
      return "\(context.debugDescription)\(Self.at(context))"
    @unknown default:
      return error.localizedDescription
    }
  }

  // "repos[0].id" rather than Foundation's "repos.Index 0.id".
  private static func at(_ context: DecodingError.Context) -> String {
    let path = context.codingPath.reduce(into: "") { path, key in
      if let index = key.intValue {
        path += "[\(index)]"
      } else {
        path += path.isEmpty ? key.stringValue : ".\(key.stringValue)"
      }
    }
    return path.isEmpty ? "" : " at \(path)"
  }
}

struct ImportedConfig: Codable {
  var config: VibesConfig
  var token: String?

  init(config: VibesConfig, token: String?) {
    self.config = config
    self.token = token
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicKey.self)
    token = try container.decodeIfPresent(String.self, forKey: DynamicKey("token"))
    if let nested = try container.decodeIfPresent(VibesConfig.self, forKey: DynamicKey("config")) {
      config = nested
      return
    }

    let identity = try container.decode(IdentityConfig.self, forKey: DynamicKey("identity"))
    var device = try container.decodeIfPresent(DeviceConfig.self, forKey: DynamicKey("device"))
      ?? DeviceConfig(id: UUID().uuidString.lowercased(), label: Host.current().localizedName ?? "Mac")
    if device.id.isEmpty {
      device.id = UUID().uuidString.lowercased()
    }
    let server = try container.decode(ServerConfig.self, forKey: DynamicKey("server"))
    let repos = try container.decodeIfPresent([RepoConfig].self, forKey: DynamicKey("repos")) ?? []
    let sharing = try container.decodeIfPresent(SharingConfig.self, forKey: DynamicKey("sharing")) ?? .defaults
    let presence = try container.decodeIfPresent(PresenceConfig.self, forKey: DynamicKey("presence")) ?? .defaults
    config = VibesConfig(
      identity: identity,
      device: device,
      server: server,
      repos: repos,
      sharing: sharing,
      presence: presence
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: DynamicKey.self)
    try container.encode(config, forKey: DynamicKey("config"))
    try container.encodeIfPresent(token, forKey: DynamicKey("token"))
  }
}

struct DynamicKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init(_ stringValue: String) {
    self.stringValue = stringValue
  }

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    self.stringValue = "\(intValue)"
    self.intValue = intValue
  }
}

enum JSONCoding {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      if let date = DateFormatters.isoWithFractional.date(from: value)
        ?? DateFormatters.iso.date(from: value) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO date: \(value)"
      )
    }
    return decoder
  }()
}

// nonisolated so both the main actor and the off-main GitScanner can parse/
// format dates. ISO8601DateFormatter is configured once and only read
// thereafter; Foundation's date formatters are safe for concurrent reads, so
// nonisolated(unsafe) is the honest annotation for these shared instances.
nonisolated enum DateFormatters {
  nonisolated(unsafe) static let isoWithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}

// Where the relay token lives. Release builds use the Keychain exclusively.
// Debug builds prefer a plaintext copy next to config.json ("token.dev",
// chmod 600): every rebuilt dev binary carries a fresh code signature, so a
// Keychain read would otherwise prompt for the login password on each
// iteration. The dev file is seeded from the Keychain once (one last prompt),
// then read thereafter; registration in a Debug build writes the file only.
// Delete token.dev to fall back to the Keychain.
struct TokenStore {
  private let keychain = KeychainStore()

  func readToken() throws -> String? {
    #if DEBUG
      if let token = readDevToken() { return token }
      let token = try keychain.readToken()
      if let token { writeDevToken(token) }
      return token
    #else
      return try keychain.readToken()
    #endif
  }

  func saveToken(_ token: String) throws {
    #if DEBUG
      writeDevToken(token)
    #else
      try keychain.saveToken(token)
    #endif
  }

  #if DEBUG
    private var devTokenURL: URL {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      return base
        .appendingPathComponent("Vibes", isDirectory: true)
        .appendingPathComponent("token.dev")
    }

    private func readDevToken() -> String? {
      guard let data = try? Data(contentsOf: devTokenURL) else { return nil }
      let token = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return token.isEmpty ? nil : token
    }

    private func writeDevToken(_ token: String) {
      let url = devTokenURL
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try? Data(token.utf8).write(to: url, options: [.atomic])
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path
      )
    }
  #endif
}

// Account hand-off between the user's Macs via iCloud Keychain: one
// synchronizable item holding the relay URL, identity, and a bearer token that
// every signed-in Mac keeps fresh on launch. A brand-new Mac on the same Apple
// ID reads it to offer one-click "continue as @handle" — it uses the synced
// token once to mint its own per-device token (POST /api/tokens) and never
// stores the synced token as its working credential.
//
// Everything here is best-effort by contract: iCloud Keychain may be off, and
// unsigned dev builds may not be able to access synchronizable items at all.
// Callers treat nil/false as "no synced account" and fall back to manual setup.
struct SyncedAccount: Codable, Equatable {
  var relayURL: URL
  var handle: String
  var displayName: String
  var token: String

  enum CodingKeys: String, CodingKey {
    case relayURL = "relay_url"
    case handle
    case displayName = "display_name"
    case token
  }
}

struct SyncedAccountStore {
  private let service = "com.marcusvorwaller.vibes.account"
  private let account = "default"

  func read() -> SyncedAccount? {
    var query = baseQuery()
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      logFailure("read", status)
      return nil
    }
    return try? JSONCoding.decoder.decode(SyncedAccount.self, from: data)
  }

  func save(_ syncedAccount: SyncedAccount) {
    guard let data = try? JSONCoding.encoder.encode(syncedAccount) else { return }
    var query = baseQuery()
    if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
      let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      logFailure("update", status)
    } else {
      query[kSecValueData as String] = data
      let status = SecItemAdd(query as CFDictionary, nil)
      logFailure("add", status)
    }
  }

  func delete() {
    logFailure("delete", SecItemDelete(baseQuery() as CFDictionary))
  }

  // Best-effort is the contract, but a dev should still be able to see the
  // OSStatus when the synchronizable keychain says no (e.g. -34018
  // errSecMissingEntitlement on builds without keychain entitlements).
  private func logFailure(_ operation: String, _ status: OSStatus) {
    #if DEBUG
      guard status != errSecSuccess && status != errSecItemNotFound else { return }
      let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
      print("SyncedAccountStore \(operation) failed: \(message) (\(status))")
    #endif
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      // The whole point of this item: ride iCloud Keychain to the user's
      // other Macs. Matching must specify it too or reads miss the item.
      kSecAttrSynchronizable as String: true
    ]
  }
}

struct KeychainStore {
  private let service = "com.marcusvorwaller.vibes.relay-token"
  private let account = "default"

  func readToken() throws -> String? {
    var query = baseQuery()
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
    guard let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func saveToken(_ token: String) throws {
    let data = Data(token.utf8)
    var query = baseQuery()
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    if status == errSecSuccess {
      let update = [kSecValueData as String: data]
      let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
      guard updateStatus == errSecSuccess else { throw KeychainError(status: updateStatus) }
    } else if status == errSecItemNotFound {
      query[kSecValueData as String] = data
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    } else {
      throw KeychainError(status: status)
    }
  }

  func deleteToken() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      throw KeychainError(status: status)
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

struct KeychainError: LocalizedError {
  var status: OSStatus
  var errorDescription: String? {
    SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
  }
}
