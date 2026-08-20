/// Port of reasonix/internal/eventwire/approval.go.
///
/// The wire approval types are implemented alongside `toWire` in `wire.dart`
/// because they are tightly coupled to the shared Event JSON contract. This
/// file preserves the Go source-file mapping and re-exports the same symbols
/// for callers that import the per-file entry point.
library;

export 'wire.dart'
    show WireApproval, WireWriteAccessApproval, WireRecoveryApproval;
