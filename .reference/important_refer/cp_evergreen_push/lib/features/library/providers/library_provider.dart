import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/library_service.dart';

final libraryServiceProvider = Provider<LibraryService>((ref) {
  final dio = ref.read(dioClientProvider);
  return LibraryService(dio);
});

final libraryBooksProvider =
    FutureProvider<Result<List<BorrowedBook>>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn || auth.ssoCookie == null) {
    return Err(AppError.configMissing('学号和密码')
      ..recoveryHint = '请先登录统一认证');
  }
  final service = ref.read(libraryServiceProvider);
  return service.getBorrowedBooks(auth.ssoCookie!.value);
});
