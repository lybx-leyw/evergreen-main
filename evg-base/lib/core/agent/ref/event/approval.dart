part of 'event.dart';

class Approval {
  String id = '';
  String tool = '';
  String subject = '';
  String reason = '';
  String rawInput = '';
  bool fresh = false;
  String kind = '';
  RecoveryApproval? recovery;
  WriteAccessApproval? writeAccess;
}

const approvalKindWriteAccess = 'write_access';

class WriteAccessApproval {
  List<String> directories = [];
  List<String> displayDirectories = [];
  String justification = '';
  bool broadHomeAccess = false;
  bool ordinaryPermissionNeeded = false;
  bool persistAllowed = false;
}

class RecoveryApproval {
  String sourceAgent = '';
  String failedTool = '';
  String failedSummary = '';
  String diagnosis = '';
  String nextTool = '';
  String nextAction = '';
  String changeKind = '';
  String changeRationale = '';
  String reviewRationale = '';
  String planBefore = '';
  String planAfter = '';
  bool canGrantTask = false;
  String taskGrantScope = '';
}

WriteAccessApproval? normalizeWriteAccessApproval(WriteAccessApproval? w) {
  if (w == null) return null;
  w.directories = List.unmodifiable(w.directories.isEmpty ? [] : w.directories);
  w.displayDirectories = List.unmodifiable(
      w.displayDirectories.isEmpty ? [] : w.displayDirectories);
  return w;
}
