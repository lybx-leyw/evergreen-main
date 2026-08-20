/// Port of reasonix/internal/shellparse/mask_test.go.
library;

import 'package:evergreen_base/core/agent/ref/shellparse/bash.dart'
    as shellparse;
import 'package:test/test.dart';

void main() {
  test('can mask earlier failure', () {
    final cases = <String, (bool, bool)>{
      'go build ./... && go test ./...': (false, true),
      'a && b && c': (false, true),
      'go test ./...': (false, true),
      '': (false, true),
      'go build ./... ; go test ./...': (true, true),
      'go build ./...\ngo test ./...': (true, true),
      'go build ./... || true': (true, true),
      'go test ./... | tee out.txt': (true, true),
      'go test ./... |& tee out.txt': (true, true),
      'sleep 5 &': (true, true),
      'a && b ; c': (true, true),
      'a ; b && c': (true, true),
      'a && b || c': (true, true),
      'if true; then go test ./...; fi': (false, false),
      'go test ./... &&': (false, false),
      'cat <<EOF\nx\nEOF': (false, false),
    };
    for (final entry in cases.entries) {
      final (canMask, ok) = shellparse.canMaskEarlierFailure(entry.key);
      expect(canMask, entry.value.$1, reason: entry.key);
      expect(ok, entry.value.$2, reason: entry.key);
    }
  });
}
