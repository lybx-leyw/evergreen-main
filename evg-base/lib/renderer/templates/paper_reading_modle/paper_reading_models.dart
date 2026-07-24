/// 论文阅读模板 V3 — 数据模型（按章节+段落）。
library;

/// 段落模型。
class ParagraphModel {
  final int index;
  final String guide;     // AI 助学导语
  final String content;   // 原文（英文）
  String translated;      // 译文（翻译后填充）

  ParagraphModel({
    required this.index,
    required this.guide,
    required this.content,
    this.translated = '',
  });

  factory ParagraphModel.fromJson(Map<String, dynamic> json, int index) =>
      ParagraphModel(
        index: index,
        guide: json['guide'] as String? ?? '',
        content: json['content'] as String? ?? '',
        translated: json['translated'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'index': index, 'guide': guide, 'content': content, 'translated': translated,
      };
}

/// 章节模型。
class ChapterModel {
  final int index;
  final String title;
  final List<ParagraphModel> paragraphs;

  ChapterModel({
    required this.index,
    required this.title,
    required this.paragraphs,
  });

  factory ChapterModel.fromJson(Map<String, dynamic> json, int index) =>
      ChapterModel(
        index: index,
        title: json['title'] as String? ?? 'Untitled',
        paragraphs: (json['paragraphs'] as List?)
                ?.asMap().entries.map((e) => ParagraphModel.fromJson(
                    e.value as Map<String, dynamic>, e.key)).toList() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'paragraphs': paragraphs.map((p) => p.toJson()).toList(),
      };
}

// ═══════════════ 保留的旧模型（笔记本等）═══════════════

enum NotebookType { innovation, survey }
enum PaperType { innovation, survey }

class PaperRecord {
  final String id;
  final String title;
  final List<String> authors;
  final String filePath;
  final PaperType paperType;
  final DateTime importedAt;
  String fullText;
  List<String> segments;
  List<Set<SectionCategory>> segmentTags;
  String? techniqueName;

  PaperRecord({
    required this.id, required this.title, required this.authors,
    required this.filePath, required this.paperType, required this.importedAt,
    this.fullText = '', this.segments = const [],
    this.segmentTags = const [], this.techniqueName,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'authors': authors, 'filePath': filePath,
    'paperType': paperType.name, 'importedAt': importedAt.toIso8601String(),
    'fullText': fullText, 'techniqueName': techniqueName,
    'segments': segments,
    'segmentTags': segmentTags.map((s) => s.map((c) => c.name).toList()).toList(),
  };

  factory PaperRecord.fromJson(Map<String, dynamic> json) => PaperRecord(
    id: json['id'] as String, title: json['title'] as String,
    authors: (json['authors'] as List).cast<String>(),
    filePath: json['filePath'] as String,
    paperType: PaperType.values.byName(json['paperType'] as String),
    importedAt: DateTime.parse(json['importedAt'] as String),
    fullText: json['fullText'] as String? ?? '',
    techniqueName: json['techniqueName'] as String?,
    segments: (json['segments'] as List?)?.cast<String>() ?? [],
    segmentTags: (json['segmentTags'] as List?)
        ?.map((s) => (s as List).map((c) => SectionCategory.values.byName(c as String)).toSet())
        .toList() ?? [],
  );
}

class TechniqueEntry {
  final String id; final String name; final String fullName;
  final String description; int orderIndex; List<String> paperIds;
  TechniqueEntry({required this.id, required this.name, required this.fullName,
    required this.description, required this.orderIndex, this.paperIds = const []});
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'fullName': fullName, 'description': description,
    'orderIndex': orderIndex, 'paperIds': paperIds,
  };
  factory TechniqueEntry.fromJson(Map<String, dynamic> json) => TechniqueEntry(
    id: json['id'] as String, name: json['name'] as String,
    fullName: json['fullName'] as String? ?? '',
    description: json['description'] as String? ?? '',
    orderIndex: json['orderIndex'] as int? ?? 0,
    paperIds: (json['paperIds'] as List?)?.cast<String>() ?? [],
  );
}

class NotebookData {
  final NotebookType type;
  final List<TechniqueEntry> techniques;
  final List<PaperRecord> papers;
  /// V3 持久化：paperId → 章节列表（含段落、导语、译文）
  final Map<String, List<ChapterModel>> chaptersData;
  /// V3 持久化：paperId → 全文
  final Map<String, String> fullTextsData;

  const NotebookData({
    required this.type,
    this.techniques = const [],
    this.papers = const [],
    this.chaptersData = const {},
    this.fullTextsData = const {},
  });

  NotebookData copyWith({
    NotebookType? type,
    List<TechniqueEntry>? techniques,
    List<PaperRecord>? papers,
    Map<String, List<ChapterModel>>? chaptersData,
    Map<String, String>? fullTextsData,
  }) =>
      NotebookData(
        type: type ?? this.type,
        techniques: techniques ?? this.techniques,
        papers: papers ?? this.papers,
        chaptersData: chaptersData ?? this.chaptersData,
        fullTextsData: fullTextsData ?? this.fullTextsData,
      );

  Map<String, dynamic> toJson() => {
    'type': type.name, 'techniques': techniques.map((t) => t.toJson()).toList(),
    'papers': papers.map((p) => p.toJson()).toList(),
    'chaptersData': chaptersData.map(
        (k, v) => MapEntry(k, v.map((ch) => ch.toJson()).toList())),
    'fullTextsData': fullTextsData,
  };
  factory NotebookData.fromJson(Map<String, dynamic> json) => NotebookData(
    type: NotebookType.values.byName(json['type'] as String),
    techniques: (json['techniques'] as List?)?.map((t) => TechniqueEntry.fromJson(t as Map<String, dynamic>)).toList() ?? [],
    papers: (json['papers'] as List?)?.map((p) => PaperRecord.fromJson(p as Map<String, dynamic>)).toList() ?? [],
    chaptersData: (json['chaptersData'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k,
            (v as List).asMap().entries.map((e) => ChapterModel.fromJson(e.value as Map<String, dynamic>, e.key)).toList()),
    ) ?? {},
    fullTextsData: (json['fullTextsData'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
    ) ?? {},
  );
}

class DraftPage {
  final int pageIndex;
  final List<List<double>> strokes;
  DraftPage({required this.pageIndex, this.strokes = const []});
  DraftPage copyWith({int? pageIndex, List<List<double>>? strokes}) =>
      DraftPage(pageIndex: pageIndex ?? this.pageIndex, strokes: strokes ?? this.strokes);
}

enum PaperReadingViewType { bookshelf, bookPages, starfield, explorationTags, reading }

// ═══════════════ 保留兼容：旧标签体系（paper_service 引用）═══════════════
enum SectionCategory { background, designPhilosophy, mathDerivation, experiment, reference, other }
const Map<SectionCategory, String> sectionCategoryLabels = {
  SectionCategory.background: '背景', SectionCategory.designPhilosophy: '设计理念',
  SectionCategory.mathDerivation: '数学推导', SectionCategory.experiment: '实验',
  SectionCategory.reference: '参考文献', SectionCategory.other: '其他',
};
const Map<SectionCategory, String> sectionCategoryDescriptions = {
  SectionCategory.background: '', SectionCategory.designPhilosophy: '',
  SectionCategory.mathDerivation: '', SectionCategory.experiment: '',
  SectionCategory.reference: '', SectionCategory.other: '',
};
