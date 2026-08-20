/// Port of reasonix/internal/sysproxy/system_other.go.
///
/// Non-Windows platforms have no OS proxy source in this package; env/direct
/// handling stays with the caller.
library;

/// Resolves the OS-level proxy for [target]. Always returns null outside the
/// Windows system-proxy implementation.
Uri? forUrl(Uri? target) => null;
