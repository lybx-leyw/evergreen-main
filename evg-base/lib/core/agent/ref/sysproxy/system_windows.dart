/// Port of reasonix/internal/sysproxy/system_windows.go.
///
/// Adapter note: the Go implementation calls WinHTTP/IE proxy APIs. The Dart
/// runtime in this repository does not yet bind WinHTTP, so this adapter keeps
/// the same observable fallback as non-Windows (return null) and lets callers
/// use env/direct. A future Windows-specific Dart FFI implementation can fill
/// this in without changing the public API.
library;

/// Resolves the Windows system proxy. Currently falls back to direct until a
/// Dart FFI WinHTTP adapter is added.
Uri? forUrl(Uri? target) => null;
