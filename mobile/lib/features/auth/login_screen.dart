import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/config/app_config.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import 'auth_controller.dart';
import '../settings/server_config_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverAddressController;
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController(text: 'admin12345');
  late String _baseUrlPreview;

  @override
  void initState() {
    super.initState();
    final serverConfig = ref.read(serverConfigControllerProvider);
    _serverAddressController = TextEditingController(
      text: serverConfig.serverAddress,
    );
    _baseUrlPreview = serverConfig.baseUrl;
    _serverAddressController.addListener(_handleServerAddressChanged);
  }

  @override
  void dispose() {
    _serverAddressController
      ..removeListener(_handleServerAddressChanged)
      ..dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final serverConfig = ref.watch(serverConfigControllerProvider);
    final palette = AppReaderPalette.of(context);
    final tablet = Responsive.isTablet(context);

    final form = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '轻阅',
            textAlign: tablet ? TextAlign.left : TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '为手机与平板重新设计的沉浸阅读入口。',
            textAlign: tablet ? TextAlign.left : TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _serverAddressController,
            decoration: InputDecoration(
              labelText: '服务地址',
              helperText: '默认端口 8080，可输入 IP、IP:端口 或完整 URL',
              suffixIcon: serverConfig.isSaving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.settings_ethernet),
            ),
            keyboardType: TextInputType.url,
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? '请输入服务地址' : null,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '当前接口: $_baseUrlPreview',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: '用户名'),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? '请输入用户名' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: '密码'),
            obscureText: true,
            validator: (value) =>
                (value == null || value.isEmpty) ? '请输入密码' : null,
          ),
          const SizedBox(height: 20),
          if (serverConfig.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                serverConfig.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (auth.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                auth.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: auth.isWorking ? null : _submit,
            child: auth.isWorking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );

    if (tablet) {
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.panel,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 32,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: form,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 64,
              ),
              child: Center(child: form),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      await ref
          .read(serverConfigControllerProvider)
          .updateAddress(_serverAddressController.text);
      await ref
          .read(authControllerProvider)
          .signIn(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );
    } catch (_) {
      // AuthController already stores the backend error for inline display.
    }
  }

  void _handleServerAddressChanged() {
    final nextPreview = AppConfig.normalizeBaseUrl(
      _serverAddressController.text,
    );
    if (nextPreview == _baseUrlPreview) {
      return;
    }
    setState(() {
      _baseUrlPreview = nextPreview;
    });
  }
}
