import 'package:evergreen_base/core/agent/ref/nilutil/nil.dart' as nilutil;
import 'package:test/test.dart';

abstract class _SampleInterface {
  void doSomething();
}

class _SampleImpl implements _SampleInterface {
  @override
  void doSomething() {}
}

void main() {
  test('isNil detects null', () {
    _SampleInterface? i;
    expect(nilutil.isNil(i), isTrue);
  });

  test('isNil rejects concrete values', () {
    _SampleInterface i = _SampleImpl();
    expect(nilutil.isNil(i), isFalse);
    expect(nilutil.isNil('x'), isFalse);
  });
}
