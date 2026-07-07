import 'package:flutter/material.dart';

/// 学年学期选择器。
class SemesterPicker extends StatelessWidget {
  final int year;
  final int semester;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int> onSemesterChanged;

  const SemesterPicker({
    super.key,
    required this.year,
    required this.semester,
    required this.onYearChanged,
    required this.onSemesterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text('学年', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: year,
            items: [2023, 2024, 2025, 2026, 2027].map((y) => DropdownMenuItem(
              value: y, child: Text('$y-${y+1}', style: const TextStyle(fontSize: 13)),
            )).toList(),
            onChanged: (v) { if (v != null) onYearChanged(v); },
          ),
          const SizedBox(width: 16),
          const Text('学期', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: semester,
            items: const [
              DropdownMenuItem(value: 3, child: Text('秋/冬', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 12, child: Text('春/夏', style: TextStyle(fontSize: 13))),
            ],
            onChanged: (v) { if (v != null) onSemesterChanged(v); },
          ),
        ],
      ),
    );
  }
}
