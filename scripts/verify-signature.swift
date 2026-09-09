import Foundation
import CryptoKit

// Public-key verification only. This tool never opens the signing Keychain.
guard CommandLine.arguments.count == 4,
      let publicKey = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[3]) else { exit(2) }
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    guard key.isValidSignature(signature, for: data) else {
        fputs("Ed25519 signature verification failed\n", stderr)
        exit(1)
    }
} catch {
    fputs("Signature verification error: \(error)\n", stderr)
    exit(1)
}
