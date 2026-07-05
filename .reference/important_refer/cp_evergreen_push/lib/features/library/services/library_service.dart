import 'package:dio/dio.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/log.dart';

/// Library service — API wrapper for api.lib.zju.edu.cn.
class LibraryService {
  final Dio _dio;

  LibraryService(this._dio);

  /// Fetch borrowed books list.
  Future<Result<List<BorrowedBook>>> getBorrowedBooks(String ssoCookie) async {
    Response res;
    try {
      res = await _dio.get(
        'https://api.lib.zju.edu.cn/aleph/bor-info',
        options:
            Options(headers: {'Cookie': 'iPlanetDirectoryPro=$ssoCookie'}),
      );
    } catch (e) {
      Log().warn('Library HTTPS failed, trying HTTP fallback', error: e);
      try {
        res = await _dio.get(
          'http://api.lib.zju.edu.cn/aleph/bor-info',
          options:
              Options(headers: {'Cookie': 'iPlanetDirectoryPro=$ssoCookie'}),
        );
      } catch (e2) {
        Log().warn('Library HTTP fallback also failed', error: e2);
        return Err(
            AppError.networkUnreachable('api.lib.zju.edu.cn'));
      }
    }

    final data = res.data;
    if (data is! Map) return Ok(<BorrowedBook>[]);

    final loans = data['loans'] as List<dynamic>? ?? [];
    return Ok(loans
        .map((e) => BorrowedBook.fromJson(e as Map<String, dynamic>))
        .toList());
  }

  /// Renew a book by barcode.
  Future<Result<bool>> renewBook(String ssoCookie, String barcode) async {
    Response res;
    try {
      res = await _dio.get(
        'https://api.lib.zju.edu.cn/aleph/renew?CON_LNG=chi&library=ZJU50&item_barcode=$barcode',
        options:
            Options(headers: {'Cookie': 'iPlanetDirectoryPro=$ssoCookie'}),
      );
    } catch (_) {
      try {
        res = await _dio.get(
          'http://api.lib.zju.edu.cn/aleph/renew?CON_LNG=chi&library=ZJU50&item_barcode=$barcode',
          options:
              Options(headers: {'Cookie': 'iPlanetDirectoryPro=$ssoCookie'}),
        );
      } catch (e) {
        return Err(
            AppError.networkUnreachable('api.lib.zju.edu.cn'));
      }
    }
    return Ok(res.data is Map &&
        (res.data['success'] == true || res.data['status'] == 'ok'));
  }
}

class BorrowedBook {
  final String title;
  final String author;
  final String barcode;
  final DateTime? borrowDate;
  final DateTime? dueDate;
  final bool isRenewable;

  const BorrowedBook({
    required this.title,
    required this.author,
    required this.barcode,
    this.borrowDate,
    this.dueDate,
    this.isRenewable = true,
  });

  factory BorrowedBook.fromJson(Map<String, dynamic> json) {
    return BorrowedBook(
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      barcode:
          json['barcode']?.toString() ?? json['item_barcode']?.toString() ?? '',
      borrowDate:
          DateTime.tryParse(json['loan_date']?.toString() ?? ''),
      dueDate: DateTime.tryParse(json['due_date']?.toString() ?? ''),
      isRenewable: json['renewable'] != false,
    );
  }

  int get daysUntilDue {
    if (dueDate == null) return 999;
    return dueDate!.difference(DateTime.now()).inDays;
  }

  String get statusLabel {
    if (daysUntilDue < 0) return '已逾期';
    if (daysUntilDue <= 7) return '即将到期';
    return '$daysUntilDue 天后到期';
  }
}
