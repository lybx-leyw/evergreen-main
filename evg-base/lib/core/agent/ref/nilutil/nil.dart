/// Port of reasonix/internal/nilutil.
library;

/// Reports whether [value] is null.
///
/// In Go this also detects a typed nil value stored behind an interface.
/// Dart has no typed-nil-interface distinction, so this is a compatibility
/// wrapper around [== null].
bool isNil(Object? value) => value == null;
