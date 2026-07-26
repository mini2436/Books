import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/theme/glass_theme.dart';
import '../../shared/utils/responsive.dart';
import '../../shared/widgets/glass_surface.dart';
import 'auth_controller.dart';
import '../settings/server_config_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverAddressController;
  late final AnimationController _backgroundController;
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController(text: 'admin12345');
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    final serverConfig = ref.read(serverConfigControllerProvider);
    _serverAddressController = TextEditingController(
      text: serverConfig.serverAddress,
    );
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
      value: 0.18,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _backgroundController.stop();
      _backgroundController.value = 0.18;
    } else {
      _backgroundController.repeat();
    }
  }

  @override
  void dispose() {
    _serverAddressController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _backgroundController.dispose();
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
          const SizedBox(height: 6),
          Text(
            '回到你的私人书架',
            textAlign: tablet ? TextAlign.left : TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _serverAddressController,
            decoration: InputDecoration(
              labelText: '服务地址',
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

    final panel = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: GlassSurface(
        level: GlassSurfaceLevel.floating,
        borderRadius: BorderRadius.circular(26),
        padding: EdgeInsets.all(tablet ? 30 : 24),
        child: form,
      ),
    );

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _LoginBackgroundPainter(
                  animation: _backgroundController,
                  palette: palette,
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: tablet ? 24 : 20,
                  vertical: tablet ? 24 : 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (tablet ? 48 : 40),
                  ),
                  child: Center(child: panel),
                ),
              ),
            ),
          ),
        ],
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
}

class _LoginBackgroundPainter extends CustomPainter {
  _LoginBackgroundPainter({required this.animation, required this.palette})
    : super(repaint: animation);

  final Animation<double> animation;
  final AppReaderPalette palette;

  static const _widePages = <_FloatingPageSpec>[
    _FloatingPageSpec(0.08, 0.16, 126, 172, -0.16, 0.1, 14),
    _FloatingPageSpec(0.25, 0.76, 104, 142, 0.12, 1.4, 11),
    _FloatingPageSpec(0.78, 0.12, 116, 158, 0.15, 2.5, 13),
    _FloatingPageSpec(0.92, 0.62, 136, 184, -0.12, 3.8, 16),
    _FloatingPageSpec(0.64, 0.88, 92, 126, 0.1, 5.1, 9),
  ];

  static const _compactPages = <_FloatingPageSpec>[
    _FloatingPageSpec(0.04, 0.12, 82, 112, -0.14, 0.2, 8),
    _FloatingPageSpec(0.92, 0.2, 86, 118, 0.13, 2.2, 9),
    _FloatingPageSpec(0.08, 0.84, 78, 106, 0.12, 4.0, 7),
    _FloatingPageSpec(0.94, 0.78, 88, 120, -0.1, 5.3, 10),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation.value * math.pi * 2;
    final compact = size.width < 600;
    final pages = compact ? _compactPages : _widePages;

    _paintPageTrails(canvas, size, phase);
    for (final page in pages) {
      _paintPage(canvas, size, page, phase, compact);
    }
    _paintBookSpines(canvas, size, phase, compact);
  }

  void _paintPageTrails(Canvas canvas, Size size, double phase) {
    final trailPaint = Paint()
      ..color = palette.accent.withValues(alpha: 0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var index = 0; index < 3; index++) {
      final offset = math.sin(phase * 0.7 + index * 1.8) * 18;
      final baseY = size.height * (0.23 + index * 0.27);
      final path = Path()
        ..moveTo(-size.width * 0.08, baseY + offset)
        ..cubicTo(
          size.width * 0.24,
          baseY - 52 - offset * 0.4,
          size.width * 0.7,
          baseY + 58 + offset * 0.35,
          size.width * 1.08,
          baseY - offset,
        );
      canvas.drawPath(path, trailPaint);
    }
  }

  void _paintPage(
    Canvas canvas,
    Size size,
    _FloatingPageSpec page,
    double phase,
    bool compact,
  ) {
    final drift = math.sin(phase + page.phase) * page.drift;
    final sway = math.cos(phase * 0.62 + page.phase) * 0.035;
    final center = Offset(size.width * page.x, size.height * page.y + drift);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: page.width,
      height: page.height,
    );
    final radius = Radius.circular(compact ? 12 : 16);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(page.rotation + sway);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.shift(const Offset(0, 7)), radius),
      Paint()..color = Colors.black.withValues(alpha: 0.025),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = palette.panel.withValues(alpha: compact ? 0.44 : 0.52),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..color = palette.accent.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    final textPaint = Paint()
      ..color = palette.ink.withValues(alpha: 0.075)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    final left = rect.left + page.width * 0.16;
    final top = rect.top + page.height * 0.2;
    for (var line = 0; line < 5; line++) {
      final widthFactor = line == 4 ? 0.42 : (line.isEven ? 0.68 : 0.58);
      final y = top + line * page.height * 0.105;
      canvas.drawLine(
        Offset(left, y),
        Offset(left + page.width * widthFactor, y),
        textPaint,
      );
    }

    final foldAmount = 0.14 + math.sin(phase * 1.2 + page.phase) * 0.025;
    final fold = Path()
      ..moveTo(rect.right - page.width * foldAmount, rect.top)
      ..lineTo(rect.right, rect.top + page.width * foldAmount)
      ..lineTo(rect.right, rect.top)
      ..close();
    canvas.drawPath(
      fold,
      Paint()..color = palette.accent.withValues(alpha: 0.1),
    );
    canvas.restore();
  }

  void _paintBookSpines(Canvas canvas, Size size, double phase, bool compact) {
    final count = compact ? 7 : 13;
    final baseWidth = size.width / count;
    for (var index = 0; index < count; index++) {
      final height =
          (compact ? 34.0 : 48.0) + (index % 4) * (compact ? 7.0 : 10.0);
      final yDrift = math.sin(phase * 0.55 + index * 0.7) * 3;
      final rect = Rect.fromLTWH(
        index * baseWidth + baseWidth * 0.16,
        size.height - height + yDrift,
        baseWidth * 0.68,
        height + 10,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()
          ..color = (index.isEven ? palette.accent : palette.ink).withValues(
            alpha: index.isEven ? 0.065 : 0.035,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LoginBackgroundPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _FloatingPageSpec {
  const _FloatingPageSpec(
    this.x,
    this.y,
    this.width,
    this.height,
    this.rotation,
    this.phase,
    this.drift,
  );

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final double phase;
  final double drift;
}
