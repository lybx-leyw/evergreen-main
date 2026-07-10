/// Form 视图——根据 [FormDescriptor] 动态渲染表单。
///
/// 公开类：[FormView]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../shared/widgets/form_field_renderer.dart';
import '../shared/widgets/empty_state.dart';

/// 动态表单视图。
///
/// 读取 [ModuleDescriptor.form] 中的 [FormDescriptor]，
/// 遍历 [FormDescriptor.fields] 渲染对应表单控件。
class FormView extends StatefulWidget {
  final FormDescriptor form;

  const FormView({super.key, required this.form});

  @override
  State<FormView> createState() => _FormViewState();
}

class _FormViewState extends State<FormView> {
  final _formKey = GlobalKey<FormState>();
  final _values = <String, dynamic>{};

  @override
  Widget build(BuildContext context) {
    final fields = widget.form.fields;

    if (fields.isEmpty) {
      return const EmptyState(
        icon: Icons.dynamic_form,
        title: '无表单字段',
        subtitle: '表单描述符未包含任何字段定义',
      );
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 动态表单字段
            for (final field in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FormFieldRenderer(
                  field: field,
                  initialValue: _values[field.key],
                  onChanged: (value) {
                    _values[field.key] = value;
                    if (widget.form.validateOnBlur) {
                      _formKey.currentState?.validate();
                    }
                  },
                ),
              ),

            const SizedBox(height: 8),

            // 提交按钮
            FilledButton(
              onPressed: _submit,
              child: Text(widget.form.submitLabel),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      // TODO: 提交表单数据
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('表单已提交')),
      );
    }
  }
}
