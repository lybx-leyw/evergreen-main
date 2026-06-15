/// 添加/编辑计划任务对话框。
library;

import 'package:flutter/material.dart';
import '../models/plan_task.dart';

class AddEditTaskDialog extends StatefulWidget {
  final PlanTask? existingTask;
  final void Function(PlanTask task) onSave;

  const AddEditTaskDialog({
    super.key,
    this.existingTask,
    required this.onSave,
  });

  @override
  State<AddEditTaskDialog> createState() => _AddEditTaskDialogState();
}

class _AddEditTaskDialogState extends State<AddEditTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  DateTime? _deadline;

  bool get _isEdit => widget.existingTask != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existingTask;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _notesCtrl = TextEditingController(text: t?.notes ?? '');
    _deadline = t?.deadline;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final task = _isEdit
        ? widget.existingTask!.copyWith(
            title: _titleCtrl.text.trim(),
            deadline: _deadline,
            notes: _notesCtrl.text.trim(),
          )
        : PlanTask.create(
            title: _titleCtrl.text.trim(),
            deadline: _deadline,
            notes: _notesCtrl.text.trim(),
          );

    widget.onSave(task);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '编辑任务' : '添加任务'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '任务名称',
                  hintText: '例如：复习数据结构',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入任务名称' : null,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '截止日期（可选）',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _deadline != null
                        ? '${_deadline!.year}-${_deadline!.month.toString().padLeft(2, '0')}-${_deadline!.day.toString().padLeft(2, '0')}'
                        : '暂不设置',
                    style: TextStyle(
                      color: _deadline != null ? null : Colors.grey,
                    ),
                  ),
                ),
              ),
              if (_deadline != null)
                TextButton(
                  onPressed: () => setState(() => _deadline = null),
                  child: const Text('清除截止日期'),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '添加一些备注...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEdit ? '保存' : '添加'),
        ),
      ],
    );
  }
}
