/// DataOrchestrator 的 Riverpod Provider。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'orchestrator.dart';
import 'cache.dart';

final dataOrchestratorProvider = FutureProvider<DataOrchestrator>((ref) async {
  await Cache.getInstance();
  return DataOrchestrator();
});
