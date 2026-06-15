import 'package:flutter_riverpod/flutter_riverpod.dart';

/// RVPN proxy state.
class RvpnState {
  final bool isRunning;
  final bool isChecking;
  final bool hasBinary;
  final String statusMessage;

  const RvpnState({
    this.isRunning = false,
    this.isChecking = true,
    this.hasBinary = false,
    this.statusMessage = '检查中...',
  });

  RvpnState copyWith({bool? isRunning, bool? isChecking, bool? hasBinary, String? statusMessage}) {
    return RvpnState(
      isRunning: isRunning ?? this.isRunning,
      isChecking: isChecking ?? this.isChecking,
      hasBinary: hasBinary ?? this.hasBinary,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

final rvpnProvider = StateProvider<RvpnState>((ref) => const RvpnState());
