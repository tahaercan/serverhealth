import Foundation
import Citadel
import NIOCore
import NIOSSH
import Crypto

enum SSHServiceError: Error, LocalizedError {
    case connectionFailed(String)
    case commandFailed(String)
    case unexpectedOutput(String)
    /// Saved host key fingerprint did not match the live one — possible MITM
    /// or the server's host key legitimately rotated. We never silently
    /// accept; the user must investigate.
    case hostKeyMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let m): return "SSH bağlantısı başarısız: \(m)"
        case .commandFailed(let m):    return "Komut hatası: \(m)"
        case .unexpectedOutput(let m): return "Beklenmeyen çıktı: \(m)"
        case .hostKeyMismatch(let exp, let act):
            return "Host key changed — expected \(exp), got \(act). Possible MITM. Delete and re-add this server to accept the new key."
        }
    }
}

/// Sanitizes credential-looking patterns out of arbitrary error strings
/// before they're persisted to LogEntry or shown in UI. Citadel/NIOSSH
/// error descriptions are generally clean, but `String(describing:)` on a
/// wrapped error can in theory dump captured context — this regex sweep
/// is a belt-and-suspenders defense for the day a dependency starts
/// including credentials in its `description`.
enum ErrorRedactor {
    private static let patterns: [String] = [
        // password=foo, pass=foo, pwd=foo  (with optional quotes)
        #"(?i)\b(pass(?:word)?|pwd)\s*=\s*"?[^"\s,]+"?"#,
        // password: foo  (colon variant)
        #"(?i)\b(pass(?:word)?|pwd)\s*:\s*"?[^"\s,]+"?"#,
        // SSH key blocks
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
        // base64-looking blobs (40+ chars) — keys, tokens
        #"\b[A-Za-z0-9+/]{40,}={0,2}\b"#,
    ]

    static func redact(_ s: String) -> String {
        var out = s
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: []) {
                let range = NSRange(out.startIndex..., in: out)
                out = regex.stringByReplacingMatches(
                    in: out, options: [], range: range, withTemplate: "[redacted]"
                )
            }
        }
        return out
    }
}

// MARK: - Host key validators (TOFU)

/// Captures the live host key's fingerprint on connect and always succeeds.
/// Used on the very first connection to a server (we don't know the key yet
/// so we can't compare). The captured fingerprint is stored back into
/// `Server.hostKeyFingerprint` so subsequent connections can verify.
///
/// **This is the "Trust On First Use" leg of TOFU. The window where an
/// attacker could substitute their own key is exactly one connection — the
/// first one. After that the fingerprint is pinned.**
private final class HostKeyCapturingValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _captured: String?

    var captured: String? {
        lock.lock(); defer { lock.unlock() }
        return _captured
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let fp = SSHFingerprint.compute(hostKey)
        lock.lock()
        _captured = fp
        lock.unlock()
        validationCompletePromise.succeed(())
    }
}

/// Compares the live host key's fingerprint against an expected value.
/// Used for every connection AFTER the first one. A mismatch fails the
/// connection — the user has to investigate (could be MITM or a legitimate
/// host key rotation; we don't second-guess).
private final class FingerprintMatchingValidator: NIOSSHClientServerAuthenticationDelegate, Sendable {
    let expected: String

    init(expected: String) { self.expected = expected }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let actual = SSHFingerprint.compute(hostKey)
        if actual == expected {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(
                SSHServiceError.hostKeyMismatch(expected: expected, actual: actual)
            )
        }
    }
}

/// Stable fingerprint of an SSH public key.
///
/// Format: `SHA256:<base64-no-padding>` — matches the `ssh-keygen -l -E sha256`
/// output you'd see when verifying a host key manually. Same key always
/// produces the same string across processes and devices, which is what we
/// need for persistence.
enum SSHFingerprint {
    static func compute(_ key: NIOSSHPublicKey) -> String {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        _ = key.write(to: &buffer)
        let bytes = buffer.readableBytesView
        let digest = SHA256.hash(data: bytes)
        let base64 = Data(digest)
            .base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))  // strip padding
        return "SHA256:\(base64)"
    }
}

// MARK: - SSH service

/// Result of running a command on a server. Carries the host key fingerprint
/// that was observed during the connection so the caller can persist it on
/// the first sight (TOFU). On subsequent calls the fingerprint is verified
/// internally and `observedFingerprint` equals the expected one.
struct CommandResult: Sendable {
    let output: String
    let observedFingerprint: String
}

actor SSHService {

    /// Uygulama boyunca tek bir SSHService aktörü kullanılır.
    /// View'lar buradan erişir; actor olduğu için thread-safe.
    static let shared = SSHService()


    // MARK: - Şifre ile bağlan + komut çalıştır

    func runCommandWithPassword(
        host: String,
        port: Int,
        username: String,
        password: String,
        command: String,
        expectedFingerprint: String? = nil
    ) async throws -> CommandResult {
        let capturer = HostKeyCapturingValidator()
        let validator: SSHHostKeyValidator
        if let expected = expectedFingerprint {
            validator = .custom(FingerprintMatchingValidator(expected: expected))
        } else {
            validator = .custom(capturer)
        }

        let settings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            hostKeyValidator: validator
        )

        let client: SSHClient
        do {
            client = try await SSHClient.connect(to: settings)
        } catch {
            throw SSHServiceError.connectionFailed(ErrorRedactor.redact(String(describing: error)))
        }

        do {
            let buffer = try await client.executeCommand(command, maxResponseSize: 1 << 20)
            try? await client.close()
            let output = String(buffer: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            let fingerprint = expectedFingerprint ?? capturer.captured ?? ""
            return CommandResult(output: output, observedFingerprint: fingerprint)
        } catch {
            try? await client.close()
            throw SSHServiceError.commandFailed(ErrorRedactor.redact(String(describing: error)))
        }
    }

    // MARK: - Key ile bağlan + komut çalıştır

    func runCommandWithKey(
        host: String,
        port: Int,
        username: String,
        privateKey: Curve25519.Signing.PrivateKey,
        command: String,
        expectedFingerprint: String? = nil
    ) async throws -> CommandResult {
        let capturer = HostKeyCapturingValidator()
        let validator: SSHHostKeyValidator
        if let expected = expectedFingerprint {
            validator = .custom(FingerprintMatchingValidator(expected: expected))
        } else {
            validator = .custom(capturer)
        }

        let settings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: { .ed25519(username: username, privateKey: privateKey) },
            hostKeyValidator: validator
        )

        let client: SSHClient
        do {
            client = try await SSHClient.connect(to: settings)
        } catch {
            throw SSHServiceError.connectionFailed(ErrorRedactor.redact(String(describing: error)))
        }

        do {
            let buffer = try await client.executeCommand(command, maxResponseSize: 1 << 20)
            try? await client.close()
            let output = String(buffer: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            let fingerprint = expectedFingerprint ?? capturer.captured ?? ""
            return CommandResult(output: output, observedFingerprint: fingerprint)
        } catch {
            try? await client.close()
            // Surface host-key mismatches directly so the engine/UI can
            // recognize them; redact everything else.
            if let typed = error as? SSHServiceError { throw typed }
            throw SSHServiceError.commandFailed(ErrorRedactor.redact(String(describing: error)))
        }
    }

    // MARK: - İlk Kurulum: şifre ile bağlan, ed25519 key üret, authorized_keys'e ekle

    struct SetupResult {
        let keyId: String                     // Keychain referansı
        let privateKey: Curve25519.Signing.PrivateKey
        let publicKeyOpenSSH: String          // ssh-ed25519 AAAA... comment
        /// Captured during the password-auth connection. Caller stores this
        /// on `Server.hostKeyFingerprint` so future connections can verify.
        let hostKeyFingerprint: String
    }

    /// Authorized_keys yorumunu cihaz adından üretir. Çağıran tarafta
    /// (genelde MainActor: View) `UIDevice.current.name` okunup buraya verilmeli.
    /// Aynı cihazdan tekrar setup yapıldığında bu yoruma eşleşen eski satır(lar)
    /// silinir, böylece duplikasyon olmaz. Başka cihazların anahtarları farklı
    /// yorumla yazıldığı için dokunulmaz.
    static func deviceComment(deviceName: String) -> String {
        // Boşluk yerine tire — sed pattern'da boşluk yönetimi sorunu yaşamamak için.
        let sanitized = deviceName
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "/", with: "-")
        return "serverhealth-ios \(sanitized)"
    }

    func setupSSHKey(
        host: String,
        port: Int,
        username: String,
        password: String,
        comment: String
    ) async throws -> SetupResult {

        let effectiveComment = comment

        // 1) Yerelde ed25519 key pair üret
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyOpenSSH = OpenSSHKey.ed25519PublicKey(
            from: privateKey.publicKey,
            comment: effectiveComment
        )

        // 2) Şifre ile bağlan — host key TOFU capture (we don't know the key
        //    yet; the captured fingerprint will be saved on the Server model
        //    and verified on every subsequent connection).
        let capturer = HostKeyCapturingValidator()
        let settings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            hostKeyValidator: .custom(capturer)
        )

        let client: SSHClient
        do {
            client = try await SSHClient.connect(to: settings)
        } catch {
            throw SSHServiceError.connectionFailed(ErrorRedactor.redact(String(describing: error)))
        }

        guard let capturedFingerprint = capturer.captured else {
            try? await client.close()
            throw SSHServiceError.connectionFailed("Host key fingerprint was not captured during handshake.")
        }

        // 3) authorized_keys idempotent setup:
        //    - Aynı cihazın eski satır(lar)ını sil (yorum eşleşmesiyle)
        //    - Yeni satırı ekle
        //    Başka cihazların anahtarları yorumlarıyla ayrıldığı için dokunulmaz.
        //
        //    Komut satırında tek tırnak kullanıldığı için public key ve comment'teki
        //    tırnakları ANSI-C escape ile kapatıyoruz. UIDevice.name sanitize edildi.
        let safePubKey = shellEscapeSingleQuotes(publicKeyOpenSSH)
        let safeCommentForSed = shellEscapeForSed(effectiveComment)

        let setupCommand = """
        set -e
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        touch ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        # Bu cihaza ait eski satırları sil (boşluktan sonra TAM comment eşleşmesi):
        sed -i.bak "/ \(safeCommentForSed)$/d" ~/.ssh/authorized_keys
        rm -f ~/.ssh/authorized_keys.bak
        # Yeni satırı ekle:
        echo '\(safePubKey)' >> ~/.ssh/authorized_keys
        echo OK
        """

        do {
            let buffer = try await client.executeCommand(setupCommand, maxResponseSize: 1 << 16)
            try? await client.close()
            let output = String(buffer: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            guard output.hasSuffix("OK") else {
                throw SSHServiceError.unexpectedOutput(output)
            }
        } catch let err as SSHServiceError {
            throw err
        } catch {
            try? await client.close()
            throw SSHServiceError.commandFailed(ErrorRedactor.redact(String(describing: error)))
        }

        // 4) Private key'i Keychain'e kaydet
        let keyId = UUID().uuidString
        try KeychainService.store(privateKey: privateKey.rawRepresentation, for: keyId)

        return SetupResult(
            keyId: keyId,
            privateKey: privateKey,
            publicKeyOpenSSH: publicKeyOpenSSH,
            hostKeyFingerprint: capturedFingerprint
        )
    }

    // MARK: - Shell escape helpers

    private func shellEscapeSingleQuotes(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    /// sed pattern içine yazılabilir hale getirir. Comment'ta zaten boşluk ve tire
    /// dışında pek bir şey olmamalı (deviceComment() sanitize ediyor) ama yine de
    /// sed'in özel karakterlerini escape edelim.
    private func shellEscapeForSed(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "/",  with: "\\/")
            .replacingOccurrences(of: "&",  with: "\\&")
            .replacingOccurrences(of: ".",  with: "\\.")
            .replacingOccurrences(of: "$",  with: "\\$")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Server modeli ile komut çalıştır (key auth, Keychain'den)

    /// Verilen Server'a key authentication ile bağlanıp komutu çalıştırır.
    /// - Keychain'den private key okunur
    /// - Server'da saved fingerprint varsa STRICT host key matching uygular
    /// - Yoksa CAPTURE eder (lenient TOFU); çağıran observedFingerprint'i
    ///   Server.hostKeyFingerprint'e yazmalı
    func runCommand(_ command: String, on creds: ServerCredentials) async throws -> CommandResult {
        let raw = try KeychainService.load(for: creds.keychainKeyId)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        return try await runCommandWithKey(
            host: creds.host,
            port: creds.port,
            username: creds.username,
            privateKey: privateKey,
            command: command,
            expectedFingerprint: creds.hostKeyFingerprint
        )
    }
}

/// SSHService SwiftData @Model türlerine doğrudan bağımlı olmasın diye
/// — actor isolation ve cross-module test kolaylığı için — sadece gereken
/// alanları taşıyan basit bir DTO. `Server` modelinden `credentials` property'si
/// ile elde edilir.
struct ServerCredentials: Sendable {
    let host: String
    let port: Int
    let username: String
    let keychainKeyId: String
    /// Saved host key fingerprint (TOFU). Nil → next connection captures
    /// and the caller writes it back to `Server.hostKeyFingerprint`.
    let hostKeyFingerprint: String?
}

extension Server {
    var credentials: ServerCredentials {
        ServerCredentials(
            host: host,
            port: port,
            username: username,
            keychainKeyId: keychainKeyId,
            hostKeyFingerprint: hostKeyFingerprint
        )
    }
}
