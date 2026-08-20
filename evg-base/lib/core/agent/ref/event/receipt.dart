part of 'event.dart';

class CompletionReceipt {
  String verdict = '';
  List<ReceiptChange> changes = [];
  List<ReceiptVerification> verifications = [];
  List<ReceiptGap> gaps = [];
  List<String> risks = [];
}

class ReceiptChange {
  String path = '';
  bool reviewed = false;
}

class ReceiptVerification {
  String command = '';
  bool passed = false;
  bool stale = false;
}

class ReceiptGap {
  String kind = '';
  String detail = '';
}
