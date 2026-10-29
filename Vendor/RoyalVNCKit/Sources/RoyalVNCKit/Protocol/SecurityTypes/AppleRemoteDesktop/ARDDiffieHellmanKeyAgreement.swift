#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Security

extension VNCProtocol.ARDAuthentication {
	struct DiffieHellmanKeyAgreement {
		let publicKey: Data
		let privateKey: Data
		let secretKey: Data

		init?(prime: Data,
			  generator: Data,
			  peerKey: Data,
			  keyLength: Int) {
			guard keyLength > 0 else {
				return nil
			}

			guard let keyPair = Self.generateKeyPair(generator: generator,
													 prime: prime,
													 keyLength: keyLength),
				  !keyPair.privateKey.isEmpty,
				  !keyPair.publicKey.isEmpty else {
				return nil
			}

			guard let secretKey = Self.computeSharedKey(prime: prime,
														peerKey: peerKey,
														privateKey: keyPair.privateKey),
				  !secretKey.isEmpty else {
				return nil
			}

			self.publicKey = keyPair.publicKey
			self.privateKey = keyPair.privateKey
			self.secretKey = secretKey
		}
	}
}

private extension VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement {
	struct KeyPair {
		let publicKey: Data
		let privateKey: Data
	}

	// LOCAL PATCH: a 512-bit private exponent instead of one as long as the prime (macOS offers
	// a 4096-bit group). Each modExp costs time in proportion to the exponent's length, and with
	// CryptoSwift's BigUInt the full-length exponent took ~0.3 s per modExp on an iPhone (14 s in
	// an unoptimised build). 512 bits keeps the exponent well above twice the group's strength.
	static let privateExponentBytes = 64

	static func generateKeyPair(generator: Data,
								prime: Data,
								keyLength: Int) -> KeyPair? {
		let bigPrivKey = BigNum()
		let bigPubKey = BigNum()

		guard let bigPrime = BigNum(data: prime),
			  let bigGenerator = BigNum(data: generator) else {
			return nil
		}

		// Generate DH private key
		repeat {
			var random = Data(count: min(privateExponentBytes, keyLength))
			let status = random.withUnsafeMutableBytes {
				SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
			}

			guard status == errSecSuccess, let candidate = BigNum(data: random) else {
				return nil
			}

			bigPrivKey.set(candidate)
		} while bigPrivKey.isZero

		let modSuccess = BigNum.modExp(y: bigPubKey,
									   g: bigGenerator,
									   x: bigPrivKey,
									   p: bigPrime)

		guard modSuccess else {
			return nil
		}

		// LOCAL PATCH: pad to the key length instead of failing when the value happens to start
		// with a zero byte (which made 1 in 256 sign-ins fail).
		guard let privKey = bigPrivKey.bigEndianData(),
			  let pubKey = bigPubKey.bigEndianData().flatMap({ $0.leftPadded(to: keyLength) }) else {
			return nil
		}

		let keyPair = KeyPair(publicKey: pubKey,
							  privateKey: privKey)

		return keyPair
	}

	static func computeSharedKey(prime: Data,
								 peerKey: Data,
								 privateKey: Data) -> Data? {
		guard let bigPrime = BigNum(data: prime),
			  let bigPrivKey = BigNum(data: privateKey),
			  let bigPeerKey = BigNum(data: peerKey) else {
			return nil
		}

		let bigSharedKey = BigNum()

		let modSuccess = BigNum.modExp(y: bigSharedKey,
									   g: bigPeerKey,
									   x: bigPrivKey,
									   p: bigPrime)

		guard modSuccess else {
			return nil
		}

		// LOCAL PATCH: the server hashes the secret at the prime's full length; pad to match.
		guard let sharedKey = bigSharedKey.bigEndianData()?.leftPadded(to: prime.count) else {
			return nil
		}

		return sharedKey
	}
}

private extension Data {
	/// Big-endian `self` with leading zero bytes up to `length`; nil if it's already longer.
	func leftPadded(to length: Int) -> Data? {
		guard count <= length else { return nil }
		return Data(count: length - count) + self
	}
}
