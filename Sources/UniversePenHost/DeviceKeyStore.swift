import Foundation
import TafelKit

/// One key per paired iPad, so a single iPad can be unpaired without touching the others.
///
/// - Every pairing hands the iPad its own random 32-byte key (TLS identity "tafel-dev-<id>").
/// - The old shared host key stays valid for iPads paired before this existed; such an iPad gets
///   its own key the next time it connects (rekey) and the shared key can then be retired.
/// - Keys live in the keychain, the list (names, dates) in the user defaults.
///
/// Used from the server queue and the main actor, hence the lock.
final class DeviceKeyStore: @unchecked Sendable {
    struct Device: Codable, Identifiable, Equatable, Sendable {
        /// Key ID (also the TLS identity suffix).
        var id: String
        var name: String
        /// The iPad's own stable ID from its hello (re-pairing the same iPad replaces its entry).
        var deviceID: String
        var pairedAt: Date
        var lastSeen: Date?
    }

    private let lock = NSLock()
    private var devices: [Device]
    private var keys: [String: Data]
    private var legacyKey: Data
    private var legacyActive: Bool
    /// Issued at pairing start, valid on the main listener before the code is even typed (no race
    /// with the iPad's first connection); becomes a device on success, is dropped otherwise.
    private var pending: (id: String, key: Data)?

    private let vault: KeyVault
    private let defaults: UserDefaults
    private static let listKey = "pairedIPads"
    private static let legacyActiveKey = "legacyPairingActive"
    private static func account(_ id: String) -> String { "ipad-key-\(id)" }

    /// `legacyKey`: the shared host key. `upgraded`: it existed before this version, so older
    /// iPads may still use it. Tests pass a `MemoryVault` and their own defaults suite.
    init(legacyKey: Data, upgraded: Bool, vault: KeyVault = KeychainVault(), defaults: UserDefaults = .standard) {
        self.legacyKey = legacyKey
        self.vault = vault
        self.defaults = defaults
        if defaults.object(forKey: Self.legacyActiveKey) == nil { defaults.set(upgraded, forKey: Self.legacyActiveKey) }
        legacyActive = defaults.bool(forKey: Self.legacyActiveKey)
        let list = (defaults.data(forKey: Self.listKey)).flatMap { try? JSONDecoder().decode([Device].self, from: $0) } ?? []
        var k: [String: Data] = [:]
        for dev in list { if let key = vault.key(Self.account(dev.id)), key.count == 32 { k[dev.id] = key } }
        devices = list.filter { k[$0.id] != nil }
        keys = k
    }

    private func storeKey(_ key: Data, _ id: String) { vault.setKey(key, Self.account(id)) }
    private func deleteKey(_ id: String) { vault.deleteKey(Self.account(id)) }

    // MARK: Reading

    var all: [Device] { lock.withLock { devices } }
    var hasLegacyPairings: Bool { lock.withLock { legacyActive } }

    /// Every key the main listener accepts right now.
    func psks() -> [(key: Data, identity: String)] {
        lock.withLock {
            var out: [(key: Data, identity: String)] = []
            // The shared key always stays in the list (rotated when retired, so nobody holds it):
            // the listener needs at least one key.
            out.append((legacyKey, HostKey.pskIdentity))
            for dev in devices { if let k = keys[dev.id] { out.append((k, HostKey.deviceIdentity(dev.id))) } }
            if let p = pending { out.append((p.key, HostKey.deviceIdentity(p.id))) }
            return out
        }
    }

    func fingerprint(of id: String) -> String? {
        lock.withLock { keys[id].map(HostKey.fingerprint) }
    }

    // MARK: Pairing

    /// A fresh key for the pairing about to start.
    func preparePairing() -> (id: String, key: Data) {
        lock.withLock {
            let p = (id: UUID().uuidString, key: HostKey.generate())
            pending = p
            return p
        }
    }

    /// The code was right: the prepared key belongs to this iPad from now on. Older entries of the
    /// same iPad are dropped (it only keeps the newest key). Returns false if nothing was prepared.
    @discardableResult
    func completePairing(id: String, name: String, deviceID: String) -> Bool {
        lock.withLock {
            guard let p = pending, p.id == id else { return false }
            pending = nil
            for old in devices where old.deviceID == deviceID { keys[old.id] = nil; deleteKey(old.id) }
            devices.removeAll { $0.deviceID == deviceID }
            storeKey(p.key, p.id)
            keys[p.id] = p.key
            devices.append(Device(id: p.id, name: name, deviceID: deviceID, pairedAt: Date(), lastSeen: Date()))
            saveLocked()
            return true
        }
    }

    /// Pairing ended without an iPad: the prepared key is worthless.
    func cancelPairing() -> Bool {
        lock.withLock {
            guard pending != nil else { return false }
            pending = nil
            return true
        }
    }

    /// An iPad connected with the shared key: give it its own key (sent to it over the encrypted
    /// connection it already has).
    func issueForLegacy(name: String, deviceID: String) -> (id: String, key: Data) {
        lock.withLock {
            let id = UUID().uuidString, key = HostKey.generate()
            for old in devices where old.deviceID == deviceID { keys[old.id] = nil; deleteKey(old.id) }
            devices.removeAll { $0.deviceID == deviceID }
            storeKey(key, id)
            keys[id] = key
            devices.append(Device(id: id, name: name, deviceID: deviceID, pairedAt: Date(), lastSeen: Date()))
            saveLocked()
            return (id, key)
        }
    }

    /// An iPad connected with its own key: remember when (and its current name).
    func touch(id: String, name: String) {
        lock.withLock {
            guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
            devices[i].lastSeen = Date()
            devices[i].name = name
            saveLocked()
        }
    }

    // MARK: Unpairing

    /// Removes one iPad. Returns its device ID (to end its session).
    func remove(_ id: String) -> String? {
        lock.withLock {
            guard let i = devices.firstIndex(where: { $0.id == id }) else { return nil }
            let dev = devices.remove(at: i)
            keys[id] = nil
            deleteKey(id)
            saveLocked()
            return dev.deviceID
        }
    }

    /// Retires the shared key: iPads that never connected since the update must pair again.
    /// Returns the new (unused) shared key for the caller to store.
    func retireLegacy() -> Data {
        lock.withLock {
            legacyKey = HostKey.generate()
            legacyActive = false
            defaults.set(false, forKey: Self.legacyActiveKey)
            return legacyKey
        }
    }

    /// Everything: all iPads and the shared key.
    func removeAll() -> Data {
        lock.withLock {
            for dev in devices { deleteKey(dev.id) }
            devices = []
            keys = [:]
            pending = nil
            saveLocked()
        }
        return retireLegacy()
    }

    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: Self.listKey)
    }
}

/// Where the iPads' keys are kept.
protocol KeyVault: AnyObject, Sendable {
    func key(_ account: String) -> Data?
    func setKey(_ key: Data, _ account: String)
    func deleteKey(_ account: String)
}

/// The app: the keychain (service "Tafel", like the shared host key).
final class KeychainVault: KeyVault, @unchecked Sendable {
    func key(_ account: String) -> Data? { Keychain.get(account: account) }
    func setKey(_ key: Data, _ account: String) { Keychain.set(key, account: account) }
    func deleteKey(_ account: String) { Keychain.delete(account: account) }
}

/// Tests: memory only, never the real keychain.
final class MemoryVault: KeyVault, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    func key(_ account: String) -> Data? { lock.withLock { items[account] } }
    func setKey(_ key: Data, _ account: String) { lock.withLock { items[account] = key } }
    func deleteKey(_ account: String) { lock.withLock { items[account] = nil } }
}
