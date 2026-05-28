import Foundation
import Citadel
import NIOCore
import Crypto

enum SSHServiceError: Error, LocalizedError {
    case connectionFailed(String)
    case commandFailed(String)
    case unexpectedOutput(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let m): return "SSH bağlantısı başarısız: \(m)"
        case .commandFailed(let m):    return "Komut hatası: \(m)"
        case .unexpectedOutput(let m): return "Beklenmeyen çıktı: \(m)"
        }
    }
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
        command: String
    ) async throws -> String {
        let settings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            hostKeyValidator: .acceptAnything()
        )

        let client: SSHClient
        do {
            client = try await SSHClient.connect(to: settings)
        } catch {
            throw SSHServiceError.connectionFailed(String(describing: error))
        }

        do {
            let buffer = try await client.executeCommand(command, maxResponseSize: 1 << 20)
            try? await client.close()
            return String(buffer: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            try? await client.close()
            throw SSHServiceError.commandFailed(String(describing: error))
        }
    }

    // MARK: - Key ile bağlan + komut çalıştır

    func runCommandWithKey(
        host: String,
        port: Int,
        username: String,
        privateKey: Curve25519.Signing.PrivateKey,
        command: String
    ) async throws -> String {
        let settings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: { .ed25519(username: username, privateKey: privateKey) },
            hostKeyValidator: .acceptAnything()
        )

        let client: SSHClient
        do {
            client = try await SSHClient.connect(to: settings)
        } catch {
            throw SSHServiceError.connectionFailed(String(describing: error))
        }

        do {
            let buffer = try await client.executeCommand(command, maxResponseSize: 1 << 20)
            try? await client.close()
            return String(buffer: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            try? await client.close()
            throw SSHServiceError.commandFailed(String(describing: error))
        }
    }

    // MARK: - İlk Kurulum: şifre ile bağlan, ed25519 key üret, authorized_keys'e ekle

    struct SetupResult {
        let keyId: String                     // Keychain referansı
        let privateKey: Curve25519.Signing.PrivateKey
        let publicKeyOpenSSH: String          // ssh-ed25519 AAAA... comment
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

        // 2) Şifre ile bağlan
        let settings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            hostKeyValidator: .acceptAnything()
        )

        let client: SSHClient
        do {
            client = try await SSHClient.connect(to: settings)
        } catch {
            throw SSHServiceError.connectionFailed(String(describing: error))
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
            throw SSHServiceError.commandFailed(String(describing: error))
        }

        // 4) Private key'i Keychain'e kaydet
        let keyId = UUID().uuidString
        try KeychainService.store(privateKey: privateKey.rawRepresentation, for: keyId)

        return SetupResult(
            keyId: keyId,
            privateKey: privateKey,
            publicKeyOpenSSH: publicKeyOpenSSH
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

    // MARK: - Key ile bağlantı testi (Keychain'den oku)

    func testKeyAuth(
        host: String,
        port: Int,
        username: String,
        keyId: String
    ) async throws -> String {
        let raw = try KeychainService.load(for: keyId)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        return try await runCommandWithKey(
            host: host, port: port, username: username,
            privateKey: privateKey, command: "echo ok && uname -n"
        )
    }

    // MARK: - Server modeli ile komut çalıştır (key auth, Keychain'den)

    /// Verilen Server'a key authentication ile bağlanıp komutu çalıştırır.
    /// Keychain'den private key okunur; bulunamazsa throw eder.
    func runCommand(_ command: String, on server: ServerCredentials) async throws -> String {
        let raw = try KeychainService.load(for: server.keychainKeyId)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        return try await runCommandWithKey(
            host: server.host,
            port: server.port,
            username: server.username,
            privateKey: privateKey,
            command: command
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
}

extension Server {
    var credentials: ServerCredentials {
        ServerCredentials(
            host: host,
            port: port,
            username: username,
            keychainKeyId: keychainKeyId
        )
    }
}
