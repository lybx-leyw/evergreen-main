import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../services/library_service.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/empty_state.dart';
import '../../../core/config/theme.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(libraryBooksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('图书馆'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(libraryBooksProvider),
          ),
        ],
      ),
      body: booksAsync.when(
        loading: () => const LoadingWidget(message: '加载借阅信息...'),
        error: (err, _) => ErrorCard(
          message: '加载失败',
          detail: err.toString(),
          onRetry: () => ref.invalidate(libraryBooksProvider),
        ),
        data: (result) => result.fold(
          (books) {
            if (books.isEmpty) {
              return const EmptyState(
                icon: Icons.local_library,
                title: '暂无借阅记录',
                subtitle: '您当前没有在借图书',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: books.length,
              itemBuilder: (_, i) {
                final book = books[i];
              final overdue = book.daysUntilDue < 0;
              final soon = book.daysUntilDue >= 0 && book.daysUntilDue <= 7;
              return Card(
                child: ListTile(
                  title: Text(book.title),
                  subtitle: Text('${book.author} · ${book.barcode}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        book.statusLabel,
                        style: TextStyle(
                          color: overdue ? AppTheme.dangerRed : (soon ? AppTheme.warningOrange : AppTheme.successGreen),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      if (book.isRenewable && !overdue)
                        TextButton(
                          onPressed: () => _renewBook(ref, book.barcode, context),
                          child: const Text('续借'),
                        ),
                    ],
                  ),
                ),
              );
            },
            );
          },
          (error) => ErrorCard(
            message: error.userMessage,
            hint: error.recoveryHint,
            onRetry: () => ref.invalidate(libraryBooksProvider),
          ),
        ),
      ),
    );
  }

  void _renewBook(WidgetRef ref, String barcode, BuildContext context) async {
    final service = ref.read(libraryServiceProvider);
    final auth = ref.read(authProvider);
    final result = await service.renewBook(auth.ssoCookie!.value, barcode);
    if (context.mounted) {
      result.fold(
        (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? '续借成功' : '续借失败')),
          );
          if (ok) ref.invalidate(libraryBooksProvider);
        },
        (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('续借失败: ${error.userMessage}')),
          );
        },
      );
    }
  }
}
