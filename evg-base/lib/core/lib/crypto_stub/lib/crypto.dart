/// Crypto stub for core module isolation.
library crypto;

// ═══════ Minimal Crypto types for compilation ═══════

class Digest {
  final List<int> bytes;
  const Digest(this.bytes);

  @override
  String toString() => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class Sha256 {
  Digest convert(List<int> data) => Digest(_hash(data));

  static List<int> _hash(List<int> data) {
    // Stub: returns a simple deterministic hash for compilation.
    int h = 0;
    for (final b in data) { h = ((h * 31) ^ b) & 0xFFFFFFFF; }
    return [h >> 24, h >> 16, h >> 8, h].map((i) => i & 0xFF).toList();
  }
}

const sha256 = Sha256();
