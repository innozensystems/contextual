import Foundation
import CryptoKit

/// SPKI (Subject Public Key Info) certificate pinning for the proxy endpoint.
/// Reads allowed pins from Info.plist key `PROXY_CERTIFICATE_PINS`.
/// Pins are base64-encoded SHA-256 hashes of the raw public key bytes
/// (SecKeyCopyExternalRepresentation). Debug builds skip pinning when no pins are configured.
final class CertificatePinning: NSObject {
    static let shared = CertificatePinning()

    /// Allowed SHA-256 base64 public-key hashes.
    let allowedPins: Set<String>

    override init() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "PROXY_CERTIFICATE_PINS") as? String ?? ""
        self.allowedPins = Self.parsePins(raw)
        super.init()
    }

    /// Testable initializer.
    init(pins: [String]) {
        self.allowedPins = Set(pins)
        super.init()
    }

    static func parsePins(_ raw: String) -> Set<String> {
        let pins = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Set(pins)
    }

    static func sha256Base64(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }

    /// Returns true if any certificate in the trust chain matches an allowed pin.
    func validate(serverTrust: SecTrust) -> Bool {
        let count = SecTrustGetCertificateCount(serverTrust)
        for i in 0..<count {
            guard let cert = SecTrustGetCertificateAtIndex(serverTrust, i) else { continue }
            if let keyHash = publicKeyHash(for: cert), allowedPins.contains(keyHash) {
                return true
            }
        }
        return false
    }

    /// Compute the SHA-256 hash of the certificate's raw public key bytes.
    func publicKeyHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }
        var error: Unmanaged<CFError>?
        guard let cfData = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            if let err = error?.takeRetainedValue() {
                print("SecKeyCopyExternalRepresentation error: \(err)")
            }
            return nil
        }
        let data = cfData as Data
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
}

extension CertificatePinning: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // If no pins configured (typical for debug), fall back to default evaluation
        guard !allowedPins.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if validate(serverTrust: serverTrust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
