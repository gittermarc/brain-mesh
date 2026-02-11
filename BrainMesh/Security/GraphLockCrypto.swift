//
//  GraphLockCrypto.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import Foundation
import CommonCrypto

enum GraphLockCrypto {

    static let defaultIterations: Int = 120_000
    static let defaultSaltLength: Int = 16
    static let defaultKeyLength: Int = 32

    struct PasswordHash: Sendable {
        let saltB64: String
        let hashB64: String
        let iterations: Int
    }

    static func makePasswordHash(
        password: String,
        iterations: Int = GraphLockCrypto.defaultIterations,
        saltLength: Int = GraphLockCrypto.defaultSaltLength,
        keyLength: Int = GraphLockCrypto.defaultKeyLength
    ) -> PasswordHash? {
        let salt = generateSalt(length: saltLength)
        guard let derived = pbkdf2SHA256(password: password, salt: salt, iterations: iterations, keyLength: keyLength) else {
            return nil
        }
        return PasswordHash(
            saltB64: salt.base64EncodedString(),
            hashB64: derived.base64EncodedString(),
            iterations: iterations
        )
    }

    static func verifyPassword(password: String, saltB64: String, hashB64: String, iterations: Int) -> Bool {
        guard let salt = Data(base64Encoded: saltB64),
              let expected = Data(base64Encoded: hashB64) else {
            return false
        }
        guard let derived = pbkdf2SHA256(password: password, salt: salt, iterations: iterations, keyLength: expected.count) else {
            return false
        }
        return constantTimeEquals(derived, expected)
    }

    static func generateSalt(length: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: max(1, length))
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        } else {
            // Fallback: not ideal, but avoids a hard crash.
            var rng = SystemRandomNumberGenerator()
            for i in 0..<bytes.count {
                bytes[i] = UInt8.random(in: 0...255, using: &rng)
            }
            return Data(bytes)
        }
    }

    private static func pbkdf2SHA256(password: String, salt: Data, iterations: Int, keyLength: Int) -> Data? {
        let iter = max(1, iterations)
        let outLen = max(1, keyLength)

        let passwordBytes = Array(password.utf8)

        var derived = Data(repeating: 0, count: outLen)
        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            salt.withUnsafeBytes { saltBytes -> Int32 in
                let saltPtr = saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                let derivedPtr = derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)

                guard let saltPtr, let derivedPtr else { return -1 }

                return CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes,
                    passwordBytes.count,
                    saltPtr,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iter),
                    derivedPtr,
                    outLen
                )
            }
        }

        guard status == kCCSuccess else { return nil }
        return derived
    }

    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }
}
