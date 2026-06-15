/// ZJU 一卡通工具——查询校园卡余额。
library;

import '../tool.dart';
import 'zju_data_source.dart';

class ZjuEcardTool extends Tool {
  final ZjuDataSource _dataSource;

  ZjuEcardTool(this._dataSource);

  @override
  String get name => 'ecard_balance';

  @override
  String get description => '查询一卡通校园卡的当前余额（BlueWare 平台暂停，暂不可用）。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final result = await _dataSource.getEcardBalance();
      if (result == null) return '暂未获取到一卡通余额数据（API 可能暂不可用）。';

      final buf = StringBuffer()
        ..write('💳 一卡通余额: ¥${result.balance.toStringAsFixed(2)}');
      if (result.cardNumber != null) {
        buf.write(' (卡号: ${result.cardNumber})');
      }
      return buf.toString();
    } catch (e) {
      return '[查询失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
