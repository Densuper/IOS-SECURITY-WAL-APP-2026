import Foundation
import CryptoKit
import Security

/// PIN verification primitive. Not yet connected to the UI or role-management flow.
/// Store only a salted verifier, never a plaintext PIN. Add throttling and an
/// administrator-managed recovery policy before production use.
enum GuardPIN {
    struct Verifier: Codable {
        let salt: Data
        let digest: Data
    }

    static func create(_ pin: String) throws -> Verifier {
        guard pin.count >= 6, pin.allSatisfy(\.isNumber) else {
            throw PINError.invalidFormat
        }
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw PINError.randomFailure }
        return Verifier(salt: salt, digest: digest(pin: pin, salt: salt))
    }

    static func verify(_ pin: String, against verifier: Verifier) -> Bool {
        let candidate = digest(pin: pin, salt: verifier.salt)
        guard candidate.count == verifier.digest.count else { return false }
        return zip(candidate, verifier.digest).reduce(0) { result, pair in
            result | Int(pair.0 ^ pair.1)
        } == 0
    }

    private static func digest(pin: String, salt: Data) -> Data {
        // PBKDF2 or a memory-hard KDF is preferred for low-entropy PINs in production.
        var data = salt
        data.append(contentsOf: pin.utf8)
        return Data(SHA256.hash(data: data))
    }

    enum PINError: Error {
        case invalidFormat
        case randomFailure
    }
}
