part of 'event.dart';

class WorkspaceMutation {
  String toolId = '';
  String toolName = '';
  List<String> paths = [];
  bool allPaths = false;
  bool content = false;
  bool tree = false;
  bool workingTree = false;
  bool gitMeta = false;
}

abstract class WorkspaceMutationSink {
  void recordWorkspaceMutation(WorkspaceMutation m);
}

void recordWorkspaceMutation(Sink s, WorkspaceMutation mutation) {
  if (nilutil.isNil(s)) return;
  if (s is WorkspaceMutationSink) {
    mutation.paths = List.unmodifiable([...mutation.paths]);
    s.recordWorkspaceMutation(mutation);
  }
}
