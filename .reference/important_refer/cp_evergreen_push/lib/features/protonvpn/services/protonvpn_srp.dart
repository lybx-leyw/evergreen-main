/// ProtonVPN SRP-6a client implementation.
///
/// Pure functions implementing the Secure Remote Password protocol
/// as used by ProtonVPN's auth flow (g=2, H=SHA256).
///
/// Protocol overview:
///   1. Client generates ephemeral key pair (secret a, public A = g^a mod N)
///   2. Server returns (salt, B = server ephemeral, N = modulus)
///   3. Client computes M1 proof using the formulas below
///   4. Client sends (A, M1) → server returns M2 (server proof)
///
/// Reference:
///   .reference/win-app/src/Api/ProtonVPN.Api/ApiClient.cs (auth flow)
///   .reference/win-app/src/Api/ProtonVPN.Api.Contracts/Auth/ (contracts)

import 'dart:convert' show base64, utf8;
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

// ═══════════════════════════════════════════════════════════
// Bytes ↔ hex (inline — no external package needed)
// ═══════════════════════════════════════════════════════════

String _bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List _hexToBytes(String hex) {
  final len = hex.length;
  if (len.isOdd) throw ArgumentError('Hex string must have even length');
  final out = Uint8List(len ~/ 2);
  for (int i = 0; i < len; i += 2) {
    out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return out;
}

// ═══════════════════════════════════════════════════════════
// Byte helpers
// ═══════════════════════════════════════════════════════════

Uint8List _sha256(Uint8List data) {
  return Uint8List.fromList(crypto.sha256.convert(data).bytes);
}

/// BigInt → unsigned big-endian bytes, minimal length.
Uint8List _bigIntToBytes(BigInt n) {
  if (n == BigInt.zero) return Uint8List(0);
  final hex = n.toRadixString(16);
  final padded = hex.length.isOdd ? '0$hex' : hex;
  return _hexToBytes(padded);
}

/// BigInt → unsigned big-endian bytes padded to exactly [length] bytes.
Uint8List _bigIntToPaddedBytes(BigInt n, int length) {
  final raw = _bigIntToBytes(n);
  if (raw.length >= length) return raw;
  final padded = Uint8List(length);
  padded.setRange(length - raw.length, length, raw);
  return padded;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  if (bytes.isEmpty) return BigInt.zero;
  return BigInt.parse(_bytesToHex(bytes), radix: 16);
}

/// Base64-decode a string to bytes (uses dart:convert under the hood).
Uint8List _base64ToBytes(String b64) {
  return Uint8List.fromList(
      base64.decode(b64.replaceAll(RegExp(r'\s'), '')));
}

/// BigInt → uppercase hex, minimal even-length.
String _bigIntToHex(BigInt n) {
  final hex = n.toRadixString(16);
  return (hex.length.isOdd ? '0$hex' : hex).toUpperCase();
}

// ═══════════════════════════════════════════════════════════
// SRP-6a constants
// ═══════════════════════════════════════════════════════════

final BigInt _g = BigInt.from(2);

// ═══════════════════════════════════════════════════════════
// Public API
// ═══════════════════════════════════════════════════════════

/// Generate a cryptographically-secure random client ephemeral secret
/// and compute the corresponding public value.
///
/// Returns `(secretA, publicA)`:
/// - `secretA`: 256-bit random secret as raw bytes
/// - `publicA`: uppercase hex string of A = g^a mod N
({Uint8List secretA, String publicA}) generateClientEphemeral(BigInt modulus) {
  // 256-bit (32-byte) cryptographically-secure random for 'a'
  final secretA = Uint8List(32);
  final rng = Random.secure();
  for (int i = 0; i < 32; i++) {
    secretA[i] = rng.nextInt(256);
  }
  final a = _bytesToBigInt(secretA);

  // A = g^a mod N
  final A = _g.modPow(a, modulus);
  final publicA = _bigIntToHex(A);

  return (secretA: secretA, publicA: publicA);
}

/// Compute the SRP-6a client proof (M1) and expected server proof (M2).
///
/// Parameters:
/// - [modulus]: the 2048-bit SRP safe prime N from auth/info (as BigInt)
/// - [serverEphemeral]: B from auth/info (as BigInt)
/// - [salt]: salt from auth/info (base64-encoded string)
/// - [username]: Proton account username
/// - [password]: Proton account password
/// - [secretA]: client secret 'a' (raw bytes from [generateClientEphemeral])
/// - [publicA]: client public 'A' (hex string from [generateClientEphemeral])
///
/// Returns `(clientProof, expectedServerProof)` — both uppercase hex strings.
({String clientProof, String expectedServerProof}) computeClientProof({
  required BigInt modulus,
  required BigInt serverEphemeral,
  required String salt,
  required String username,
  required String password,
  required Uint8List secretA,
  required String publicA,
}) {
  final N = modulus;
  final B = serverEphemeral;
  final N_bytes = _bigIntToBytes(N);
  final N_len = N_bytes.length;

  // ── identity hash: SHA256(username | ":" | password) ──
  final identityBytes =
      Uint8List.fromList(utf8.encode('$username:$password'));
  final identityHash = _sha256(identityBytes);

  // ── decode salt (base64 → bytes) ──
  final saltBytes = _base64ToBytes(salt);

  // ── x = SHA256(salt_bytes | SHA256(username | ":" | password)) ──
  final xConcat = Uint8List(saltBytes.length + identityHash.length)
    ..setAll(0, saltBytes)
    ..setAll(saltBytes.length, identityHash);
  final x = _bytesToBigInt(_sha256(xConcat));

  // ── B as hex ──
  final B_hex = _bigIntToHex(B);

  // ── u = SHA256(A_hex | B_hex) as BigInt ──
  final uConcat =
      Uint8List.fromList(utf8.encode('$publicA$B_hex'));
  final u = _bytesToBigInt(_sha256(uConcat));

  // ── k = SHA256(N_bytes | padded_g) ──
  // g is padded to N_len bytes (0x00...0x02)
  final padded_g = Uint8List(N_len);
  padded_g[N_len - 1] = 2;
  final kConcat = Uint8List(N_len * 2)
    ..setAll(0, N_bytes)
    ..setAll(N_len, padded_g);
  final k = _bytesToBigInt(_sha256(kConcat));

  // ── a (client secret) ──
  final a = _bytesToBigInt(secretA);
  final ux = u * x;

  // ── g^x mod N ──
  final gx = _g.modPow(x, N);

  // ── S = (B - k * g^x)^(a + u * x) mod N ──
  var base = B - k * gx;
  base = base % N;
  final S = base.modPow(a + ux, N);

  // ── K = SHA256(S as N_len bytes) ──
  final S_bytes = _bigIntToPaddedBytes(S, N_len);
  final K_hash = _sha256(S_bytes);
  final K_hex = _bytesToHex(K_hash);

  // ── M1 = SHA256(H(N)⊕H(g) | H(username) | salt | A | B | K) ──
  final hN = _sha256(N_bytes);
  final hg = _sha256(padded_g);
  final hNxorHg = Uint8List(32);
  for (int i = 0; i < 32; i++) {
    hNxorHg[i] = hN[i] ^ hg[i];
  }

  final usernameHash =
      _sha256(Uint8List.fromList(utf8.encode(username)));

  final m1Builder = BytesBuilder(copy: false)
    ..add(hNxorHg)
    ..add(usernameHash)
    ..add(saltBytes)
    ..add(utf8.encode(publicA))
    ..add(utf8.encode(B_hex))
    ..add(K_hash);
  final M1 = _bytesToHex(_sha256(m1Builder.toBytes()));

  // ── M2 = SHA256(A | M1 | K) ──
  final m2Builder = BytesBuilder(copy: false)
    ..add(utf8.encode(publicA))
    ..add(utf8.encode(M1))
    ..add(K_hash);
  final M2 = _bytesToHex(_sha256(m2Builder.toBytes()));

  return (clientProof: M1, expectedServerProof: M2);
}
