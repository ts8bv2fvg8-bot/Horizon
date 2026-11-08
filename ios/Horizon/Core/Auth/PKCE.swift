import CryptoKit
import Foundation

/// RFC 7636 Proof Key for Code Exchange. Planning Center requires PKCE for public clients
/// such as mobile apps, which can't keep a client secret.
struct PKCE {
    let verifier: String
    let challenge: String
    let method = "S256"

    init(verifier: String = PKCE.randomURLSafeString(byteCount: 32)) {
        self.verifier = verifier
        self.challenge = PKCE.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
