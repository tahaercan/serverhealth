import Foundation
import Crypto

enum OpenSSHKey {

    /// Build an OpenSSH-format public key line for an Ed25519 key.
    /// Format: `ssh-ed25519 <base64-blob> <comment>`
    ///
    /// Wire format of the base64 blob:
    ///   string "ssh-ed25519"   (uint32 length prefix + bytes)
    ///   string <raw 32-byte public key>
    static func ed25519PublicKey(
        from publicKey: Curve25519.Signing.PublicKey,
        comment: String
    ) -> String {
        var blob = Data()
        append(string: "ssh-ed25519", to: &blob)
        append(string: publicKey.rawRepresentation, to: &blob)

        let b64 = blob.base64EncodedString()
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedComment.isEmpty
            ? "ssh-ed25519 \(b64)"
            : "ssh-ed25519 \(b64) \(trimmedComment)"
    }

    // MARK: - Wire helpers (SSH "string" encoding: uint32 BE length + bytes)

    private static func append(string s: String, to data: inout Data) {
        append(string: Data(s.utf8), to: &data)
    }

    private static func append(string bytes: Data, to data: inout Data) {
        var len = UInt32(bytes.count).bigEndian
        withUnsafeBytes(of: &len) { data.append(contentsOf: $0) }
        data.append(bytes)
    }
}
