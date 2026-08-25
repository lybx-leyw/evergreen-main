/// SSE 帧序列化测试 —— 验证 data 层 `event: <name>\ndata: {...}\n\n` 帧格式约定。
///
/// 纯 Dart，覆盖 [sse_frame.dart] 四个帧构造函数与 [DataChangeEvent].toJson。

import 'dart:convert';

import 'package:test/test.dart';

import '../sse_frame.dart';
import '../data_diff.dart';

void main() {
  group('data 流 SSE 帧', () {
    test('data 帧格式：event: data\\ndata: {"name":..., "data":...}\\n\\n', () {
      final frame = dataStreamSseFrame('camera', {'t': 1});
      expect(frame, 'event: data\ndata: {"name":"camera","data":{"t":1}}\n\n');
    });

    test('data 帧：Map/List/标量均 JSON 编码', () {
      expect(dataStreamSseFrame('x', [1, 2]), contains('"data":[1,2]'));
      expect(dataStreamSseFrame('x', 'hello'), contains('"data":"hello"'));
      expect(dataStreamSseFrame('x', null), contains('"data":null'));
    });

    test('data 帧：非 JSON 对象回退 toString 不抛', () {
      // Uri 是 dart:core 对象，jsonEncode 无法直接编码 → 回退字符串
      final frame = dataStreamSseFrame('x', Uri.parse('http://a/b'));
      expect(frame, startsWith('event: data\ndata: '));
      expect(frame, endsWith('\n\n'));
      expect(frame, contains('"data":"http://a/b"'));
    });

    test('error 帧格式', () {
      final frame = dataStreamErrorSseFrame('camera', Exception('boom'));
      expect(frame,
          'event: error\ndata: {"name":"camera","error":"Exception: boom"}\n\n');
    });

    test('done 帧格式', () {
      expect(dataStreamDoneSseFrame('camera'),
          'event: done\ndata: {"name":"camera"}\n\n');
    });

    test('帧以双换行结尾（SSE 事件分隔）', () {
      expect(dataStreamSseFrame('x', {'a': 1}), endsWith('\n\n'));
      expect(dataStreamErrorSseFrame('x', 'e'), endsWith('\n\n'));
      expect(dataStreamDoneSseFrame('x'), endsWith('\n\n'));
    });
  });

  group('变更事件 SSE 帧', () {
    test('change 帧携带 DataChangeEvent.toJson 负载', () {
      final event = DataChangeEvent(
        sourceName: 'zju_scores',
        displayName: '成绩单',
        diff: computeDataDiff({'a': 1}, {'a': 2, 'b': 3}),
        at: DateTime.utc(2026, 8, 25, 12, 0, 0),
      );
      final frame = changeEventSseFrame(event);
      expect(frame, startsWith('event: change\ndata: '));
      final payload =
          jsonDecode(frame.substring('event: change\ndata: '.length).trim())
              as Map<String, dynamic>;
      expect(payload['sourceName'], 'zju_scores');
      expect(payload['displayName'], '成绩单');
      expect((payload['diff'] as Map)['changed'], 1);
      expect((payload['diff'] as Map)['added'], 1);
      expect(payload['at'], '2026-08-25T12:00:00.000Z');
    });

    test('DataChangeEvent.toJson 结构完整', () {
      final event = DataChangeEvent(
        sourceName: 's',
        displayName: 'd',
        diff: computeDataDiff({'a': 1}, {'a': 1}),
        at: DateTime.utc(2026),
      );
      final json = event.toJson();
      expect(json.keys, containsAll(['sourceName', 'displayName', 'diff', 'at']));
      expect((json['diff'] as Map).keys,
          containsAll(['added', 'removed', 'changed', 'addedItems', 'removedItems', 'changedItems']));
    });
  });
}
