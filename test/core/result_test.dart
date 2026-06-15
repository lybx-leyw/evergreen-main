import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/result.dart';
import 'package:evergreen_multi_tools/core/errors.dart';

void main() {
  // ── Ok.map ────────────────────────────────────────────────────────

  test('Ok.map — 对 Ok 值应用映射函数，返回新 Ok', () {
    final result = const Ok<int>(42);
    final mapped = result.map((v) => v.toString());

    expect(mapped.isOk, isTrue);
    expect((mapped as Ok<String>).value, '42');
  });

  // ── Err.map ───────────────────────────────────────────────────────

  test('Err.map — 错误透传，映射函数不被调用', () {
    final error = AppError.unknown(Exception('test'));
    final result = Err<int>(error);
    var called = false;
    final mapped = result.map((v) {
      called = true;
      return v.toString();
    });

    expect(mapped.isErr, isTrue);
    expect(called, isFalse);
    expect((mapped as Err<String>).error, same(error));
  });

  // ── Ok.flatMap ────────────────────────────────────────────────────

  test('Ok.flatMap — 链式调用，返回内层 Result', () {
    final result = const Ok<int>(10);
    final flatMapped = result.flatMap((v) => Ok(v * 2));

    expect(flatMapped.isOk, isTrue);
    expect((flatMapped as Ok<int>).value, 20);
  });

  // ── Err.flatMap ───────────────────────────────────────────────────

  test('Err.flatMap — 错误透传，flatMap 函数不被调用', () {
    final error = AppError.timeout(5, 'http://example.com');
    final result = Err<int>(error);
    var called = false;
    final flatMapped = result.flatMap((v) {
      called = true;
      return Ok(v * 2);
    });

    expect(flatMapped.isErr, isTrue);
    expect(called, isFalse);
    expect((flatMapped as Err<int>).error, same(error));
  });

  // ── Ok.unwrap ─────────────────────────────────────────────────────

  test('Ok.unwrap — 返回内部值', () {
    const result = Ok<String>('hello');
    expect(result.unwrap(), 'hello');
  });

  // ── Err.unwrap ────────────────────────────────────────────────────

  test('Err.unwrap — 抛出 AppError', () {
    final error = AppError.unknown(Exception('crash'));
    final result = Err<String>(error);

    expect(
      () => result.unwrap(),
      throwsA(same(error)),
    );
  });

  // ── Ok.unwrapOr ───────────────────────────────────────────────────

  test('Ok.unwrapOr — 返回内部值，不返回 default', () {
    const result = Ok<String>('real');
    expect(result.unwrapOr('default'), 'real');
  });

  // ── Err.unwrapOr ──────────────────────────────────────────────────

  test('Err.unwrapOr — 返回 default 值', () {
    final result = Err<String>(AppError.unknown(Exception('x')));
    expect(result.unwrapOr('fallback'), 'fallback');
  });

  // ── Ok.fold ───────────────────────────────────────────────────────

  test('Ok.fold — 调用 onOk 分支', () {
    const result = Ok<int>(99);
    final folded = result.fold(
      (v) => 'ok: $v',
      (e) => 'err: ${e.userMessage}',
    );
    expect(folded, 'ok: 99');
  });

  // ── Err.fold ──────────────────────────────────────────────────────

  test('Err.fold — 调用 onErr 分支', () {
    final error = AppError.timeout(10, 'url');
    final result = Err<int>(error);
    final folded = result.fold(
      (v) => 'ok: $v',
      (e) => 'err: ${e.userMessage}',
    );
    expect(folded, contains('超时'));
  });

  // ── isOk / isErr ──────────────────────────────────────────────────

  test('Ok.isOk 为 true，isErr 为 false', () {
    const result = Ok<int>(1);
    expect(result.isOk, isTrue);
    expect(result.isErr, isFalse);
  });

  test('Err.isOk 为 false，isErr 为 true', () {
    final result = Err<int>(AppError.unknown(Exception('x')));
    expect(result.isOk, isFalse);
    expect(result.isErr, isTrue);
  });

  // ── Result.fromThrowable ──────────────────────────────────────────

  test('Result.fromThrowable — 正常函数返回 Ok', () async {
    final result = await Result.fromThrowable(() async => 42);

    expect(result.isOk, isTrue);
    expect((result as Ok<int>).value, 42);
  });

  test('Result.fromThrowable — 抛出异常的函数返回 Err(UnknownError)',
      () async {
    final result = await Result.fromThrowable<int>(
        () async => throw Exception('boom'));

    expect(result.isErr, isTrue);
    final err = (result as Err<int>).error;
    expect(err, isA<UnknownError>());
    expect(err.userMessage, contains('未知错误'));
  });

  test('Result.fromThrowable — Future 正常完成', () async {
    final result =
        await Result.fromThrowable(() => Future.value('done'));

    expect(result.isOk, isTrue);
    expect((result as Ok<String>).value, 'done');
  });

  test('Result.fromThrowable — 网络超时异常', () async {
    final result = await Result.fromThrowable<String>(() async {
      // ignore: only_throw_errors
      throw TimeoutException('timed out');
    });

    expect(result.isErr, isTrue);
    expect((result as Err<String>).error, isA<UnknownError>());
  });

  // ── 相等性 ────────────────────────────────────────────────────────

  test('Ok == 按值比较', () {
    expect(const Ok(42), const Ok(42));
    expect(const Ok(42), isNot(const Ok(43)));
    expect(const Ok(42), isNot(Err(AppError.unknown(Exception('x')))));
  });

  test('Ok.hashCode 与值一致', () {
    expect(const Ok(42).hashCode, 42.hashCode);
  });
}
