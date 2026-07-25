import 'package:flutter/material.dart';

class PasswordChangeValues {
  const PasswordChangeValues({this.currentPassword, required this.newPassword});

  final String? currentPassword;
  final String newPassword;
}

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({
    super.key,
    required this.title,
    required this.description,
    this.requireCurrentPassword = false,
  });

  final String title;
  final String description;
  final bool requireCurrentPassword;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureText = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.description),
              const SizedBox(height: 18),
              if (widget.requireCurrentPassword) ...[
                TextFormField(
                  controller: _currentPasswordController,
                  obscureText: _obscureText,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '当前密码'),
                  validator: (value) =>
                      value == null || value.isEmpty ? '请输入当前密码' : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureText,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '新密码',
                  helperText: '至少 6 位',
                  suffixIcon: IconButton(
                    tooltip: _obscureText ? '显示密码' : '隐藏密码',
                    onPressed: () => setState(() {
                      _obscureText = !_obscureText;
                    }),
                    icon: Icon(
                      _obscureText
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.length < 6
                    ? '新密码至少 6 位'
                    : value.length > 128
                    ? '新密码不能超过 128 位'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureText,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: '确认新密码'),
                validator: (value) =>
                    value != _newPasswordController.text ? '两次输入的密码不一致' : null,
                onFieldSubmitted: (_) => _submit(),
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
        FilledButton(onPressed: _submit, child: const Text('确认修改')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      PasswordChangeValues(
        currentPassword: widget.requireCurrentPassword
            ? _currentPasswordController.text
            : null,
        newPassword: _newPasswordController.text,
      ),
    );
  }
}
