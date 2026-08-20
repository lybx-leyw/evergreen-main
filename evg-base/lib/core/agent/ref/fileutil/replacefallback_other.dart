/// Port of reasonix/internal/fileutil/replacefallback_other.go.
///
/// Cross-device detection is best-effort on Dart; we rely on the fallback path
/// in atomicwrite to handle EXDEV-like failures.
library;

export 'atomicwrite.dart' show replaceFile, claimRename;
