/// ZDBK 正则模式——集中管理 HTML 解析正则，便于 ZDBK 改版时快速定位。
class ZdbkPatterns {
  ZdbkPatterns._();

  /// 提取 items JSON 数组——以 "limit" 为后缀边界。
  static final RegExp itemsWithLimit = RegExp(
    r'(?<="items":)\[(.*?)\](?=,"limit")',
    dotAll: true,
  );

  /// 提取 items JSON 数组——以 "totalResult" 为后缀边界。
  static final RegExp itemsWithTotalResult = RegExp(
    r'(?<="items":)\[(.*?)\](?=,"totalResult")',
    dotAll: true,
  );

  /// 课表 kbList JSON 数组——从 "xh" 前的 JSON 块提取。
  static final RegExp timetableKbList = RegExp(
    r'(?<="kbList":)\[(.*?)\](?=,"xh")',
    dotAll: true,
  );

  /// 实践分数表格行（第二/三/四课堂成绩）。
  static final RegExp practiceScoreRow = RegExp(
    r'<tr>.*?<td[^>]*>.*?</td>.*?<td[^>]*>(.*?)</td>.*?<td[^>]*>(.*?)</td>.*?</tr>',
    dotAll: true,
  );

  /// 执行 token——CAS 登录页的 `execution` 字段。
  static final RegExp executionToken = RegExp(
    r'name="execution"\s+value="([^"]+)"',
  );
}
