/// Port of reasonix/internal/eventwire/receipt.go.
///
/// The wire completion-receipt types are implemented alongside `toWire` in
/// `wire.dart` because they share the Event JSON conversion helpers. This file
/// preserves the Go source-file mapping and re-exports the same symbols for
/// callers that import the per-file entry point.
library;

export 'wire.dart'
    show
        WireCompletionReceipt,
        WireReceiptChange,
        WireReceiptVerification,
        WireReceiptGap;
