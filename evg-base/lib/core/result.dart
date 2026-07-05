import 'errors.dart';
import 'log.dart';

/// 操作结果：要么成功携带值 [T]，要么失败携带 [AppError]。
///
/// 使用 Dart 3 的 `sealed class`，编译器在 `switch` 中可以穷尽检查
/// `Ok` 和 `Err` 两个分支，漏掉任何一个都会编译报错。
///
/// ```dart
/// // 使用示例
/// final result = await service.login(username, password);
/// return result.fold(
///   (cookie) => Text('登录成功'),
///   (error)  => ErrorCard(message: error.userMessage),
/// );
/// ```
sealed class Result<T> {
  const Result();

  /// 映射成功值：若为 [Ok]，对值应用 [fn] 并包装为新 [Ok]；若为 [Err]，错误透传。
  Result<U> map<U>(U Function(T value) fn);

  /// 串联操作：若为 [Ok]，调用 [fn] 返回下一个 [Result]；若为 [Err]，错误透传。
  ///
  /// 用于链式调用，避免嵌套 if-else：
  /// ```dart
  /// final result = parseBody(raw)
  ///     .flatMap((body) => validate(body))
  ///     .flatMap((data) => saveToDb(data));
  /// ```
  Result<U> flatMap<U>(Result<U> Function(T value) fn);

  /// 解包：成功返回值，失败抛出 [AppError]。
  ///
  /// ⚠️ 仅在确定结果为 [Ok] 时使用，否则会抛出异常。
  /// 大多数场景用 [fold] 或 [unwrapOr] 更安全。
  T unwrap();

  /// 解包：成功返回值，失败返回 [defaultValue]。
  T unwrapOr(T defaultValue);

  /// 模式匹配：分别处理成功和失败分支。
  U fold<U>(U Function(T value) onOk, U Function(AppError err) onErr);

  /// 是否成功。
  bool get isOk;

  /// 是否失败。
  bool get isErr;

  /// 适配器：包装未迁移的 Service 方法，使其返回 [Result]。
  ///
  /// 用于渐进迁移场景——旧 Service 方法仍然 throw exception，
  /// 通过此方法包装后即可返回 [Result<T>]，无需立即重写 Service。
  ///
  /// ```dart
  /// // 旧代码（throw Exception）
  /// Future<Cookie> oldLogin(String u, String p) async { ... }
  ///
  /// // 用适配器包装
  /// final result = await Result.fromThrowable(() => oldLogin(u, p));
  /// ```
  static Future<Result<T>> fromThrowable<T>(
      Future<T> Function() fn) async {
    try {
      return Ok(await fn());
    } catch (e, stack) {
      Log().error('Unhandled exception in fromThrowable',
          error: e, stack: stack);
      return Err(AppError.unknown(e));
    }
  }
}

/// 成功分支：携带操作结果值 [value]。
final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);

  @override
  Result<U> map<U>(U Function(T value) fn) => Ok(fn(value));

  @override
  Result<U> flatMap<U>(Result<U> Function(T value) fn) => fn(value);

  @override
  T unwrap() => value;

  @override
  T unwrapOr(T defaultValue) => value;

  @override
  U fold<U>(U Function(T value) onOk, U Function(AppError err) onErr) =>
      onOk(value);

  @override
  bool get isOk => true;

  @override
  bool get isErr => false;

  @override
  bool operator ==(Object other) =>
      other is Ok<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ok($value)';
}

/// 失败分支：携带 [AppError] 错误信息。
final class Err<T> extends Result<T> {
  final AppError error;
  const Err(this.error);

  @override
  Result<U> map<U>(U Function(T value) fn) => Err(error);

  @override
  Result<U> flatMap<U>(Result<U> Function(T value) fn) => Err(error);

  @override
  T unwrap() => throw error;

  @override
  T unwrapOr(T defaultValue) => defaultValue;

  @override
  U fold<U>(U Function(T value) onOk, U Function(AppError err) onErr) =>
      onErr(error);

  @override
  bool get isOk => false;

  @override
  bool get isErr => true;

  @override
  bool operator ==(Object other) =>
      other is Err<T> && other.error == error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Err($error)';
}
