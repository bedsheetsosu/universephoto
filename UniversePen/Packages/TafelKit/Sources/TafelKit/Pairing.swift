import Foundation
import CryptoKit

/// One-time pairing code shown on the Mac and typed on the iPad.
///
/// 12 symbols from Crockford Base32 = 60 bits of entropy. The code only protects the short
/// pairing exchange (the Mac opens the pairing listener for 2 minutes and closes it after the
/// first successful pairing). After pairing, connections use a random 256-bit host key.
public enum PairingCode {
    public static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    public static let length = 12

    public static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(rng.next(upperBound: UInt32(alphabet.count)))] })
    }

    /// Accepts user input with dashes/spaces, lowercase and the usual Crockford look-alikes.
    public static func normalize(_ input: String) -> String? {
        var out = ""
        for ch in input.uppercased() {
            switch ch {
            case "-", " ", "\t": continue
            case "O": out.append("0")
            case "I", "L": out.append("1")
            case "U": return nil
            default:
                guard alphabet.contains(ch) else { return nil }
                out.append(ch)
            }
        }
        return out.count == length ? out : nil
    }

    public static func formatted(_ code: String) -> String {
        stride(from: 0, to: code.count, by: 4).map { i -> String in
            let s = code.index(code.startIndex, offsetBy: i)
            let e = code.index(s, offsetBy: min(4, code.count - i))
            return String(code[s..<e])
        }.joined(separator: "-")
    }

    /// TLS pre-shared key for the pairing listener.
    public static func pairingPSK(code: String) -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(code.utf8)),
            salt: Data("tafel-pairing-v1".utf8),
            info: Data("tls-psk".utf8),
            outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }

    public static let pskIdentity = "tafel-pair"
}

public enum HostKey {
    public static let pskIdentity = "tafel-host"

    /// TLS identity of one iPad's own key.
    public static func deviceIdentity(_ keyID: String) -> String { "tafel-dev-" + keyID }

    public static func generate() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// Short fingerprint shown on both devices so the user can see they share the same key.
    public static func fingerprint(_ key: Data) -> String {
        let digest = SHA256.hash(data: key)
        return digest.prefix(4).map { String(format: "%02X", $0) }.joined()
    }
}
