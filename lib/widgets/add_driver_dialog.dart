import 'package:flutter/material.dart';

import 'package:orderly_app/theme/app_theme.dart';

/// يفتح حواراً لإضافة عامل توصيل جديد.
///
/// [existingNames] أسماء العمال الحاليين لمنع تكرار الاسم.
/// يُرجع اسم العامل بعد التحقق منه، أو `null` عند الإلغاء.
Future<String?> showAddDriverDialog(
  BuildContext context, {
  required List<String> existingNames,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) =>
        AddDriverDialog(existingNames: existingNames),
  );
}

/// حوار إدخال اسم عامل جديد.
class AddDriverDialog extends StatefulWidget {
  const AddDriverDialog({super.key, required this.existingNames});

  /// أسماء العمال المسجّلين حالياً.
  final List<String> existingNames;

  @override
  State<AddDriverDialog> createState() => _AddDriverDialogState();
}

class _AddDriverDialogState extends State<AddDriverDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'أدخل اسم العامل');
      return;
    }
    if (widget.existingNames.contains(name)) {
      setState(() => _error = 'هذا الاسم مسجّل مسبقاً');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_add_alt_1_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('إضافة عامل جديد', style: text.titleMedium)),
        ],
      ),
      content: TextField(
        key: const ValueKey<String>('driver-name-field'),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.words,
        onChanged: (String _) {
          if (_error != null) {
            setState(() => _error = null);
          }
        },
        onSubmitted: (String _) => _submit(),
        decoration: InputDecoration(
          labelText: 'اسم العامل',
          hintText: 'مثال: أحمد',
          prefixIcon: const Icon(Icons.badge_outlined, size: 20),
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey<String>('add-driver-submit'),
          onPressed: _submit,
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}
