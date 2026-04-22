import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../shared/utils/responsive.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static Widget buildBranchContainer(
    BuildContext context,
    StatefulNavigationShell navigationShell,
    List<Widget> children,
  ) {
    return _AnimatedBranchContainer(
      currentIndex: navigationShell.currentIndex,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablet = Responsive.isTablet(context);
    final canAccessAdmin = ref.watch(
      authControllerProvider.select(
        (auth) => auth.user?.canAccessAdmin ?? false,
      ),
    );
    final visibleBranchIndexes = canAccessAdmin
        ? const [0, 1, 2, 3]
        : const [0, 1, 3];
    final selectedIndex = visibleBranchIndexes.indexOf(
      navigationShell.currentIndex,
    );

    if (tablet) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
              onDestinationSelected: (index) =>
                  _onDestinationSelected(index, visibleBranchIndexes),
              labelType: NavigationRailLabelType.all,
              destinations: [
                const NavigationRailDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: Text('书架'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.sticky_note_2_outlined),
                  selectedIcon: Icon(Icons.sticky_note_2),
                  label: Text('批注'),
                ),
                if (canAccessAdmin)
                  const NavigationRailDestination(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    selectedIcon: Icon(Icons.admin_panel_settings),
                    label: Text('后台'),
                  ),
                const NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('我'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: (index) =>
            _onDestinationSelected(index, visibleBranchIndexes),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
          const NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            selectedIcon: Icon(Icons.sticky_note_2),
            label: '批注',
          ),
          if (canAccessAdmin)
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings),
              label: '后台',
            ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我',
          ),
        ],
      ),
    );
  }

  void _onDestinationSelected(int index, List<int> visibleBranchIndexes) {
    final actualBranchIndex = visibleBranchIndexes[index];
    navigationShell.goBranch(
      actualBranchIndex,
      initialLocation: actualBranchIndex == navigationShell.currentIndex,
    );
  }
}

class _AnimatedBranchContainer extends StatefulWidget {
  const _AnimatedBranchContainer({
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<_AnimatedBranchContainer> createState() =>
      _AnimatedBranchContainerState();
}

class _AnimatedBranchContainerState extends State<_AnimatedBranchContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  late int _previousIndex;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) {
      return;
    }
    _forward = widget.currentIndex > oldWidget.currentIndex;
    _previousIndex = oldWidget.currentIndex;
    _controller
      ..stop()
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stackItems = List<Widget>.generate(widget.children.length, (index) {
      final isActive = index == widget.currentIndex;
      return _BranchContainer(
        isActive: isActive,
        child: widget.children[index],
      );
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        IndexedStack(index: widget.currentIndex, children: stackItems),
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              if (!_controller.isAnimating) {
                return const SizedBox.shrink();
              }
              return _PageTurnOverlay(
                progress: _animation.value,
                forward: _forward,
                previousIndex: _previousIndex,
                currentIndex: widget.currentIndex,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BranchContainer extends StatelessWidget {
  const _BranchContainer({required this.isActive, required this.child});

  final bool isActive;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !isActive,
      child: TickerMode(enabled: isActive, child: child),
    );
  }
}

class _PageTurnOverlay extends StatelessWidget {
  const _PageTurnOverlay({
    required this.progress,
    required this.forward,
    required this.previousIndex,
    required this.currentIndex,
  });

  final double progress;
  final bool forward;
  final int previousIndex;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final shadowStrength = (1 - progress) * 0.20;
    final highlightStrength = (1 - progress) * 0.12;
    final sweep = 0.22 + ((1 - progress) * 0.26);
    final alignment = forward ? Alignment.centerRight : Alignment.centerLeft;
    final begin = forward ? Alignment.centerRight : Alignment.centerLeft;
    final end = forward ? Alignment.centerLeft : Alignment.centerRight;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: begin,
                end: end,
                colors: [
                  Colors.black.withValues(alpha: shadowStrength * 0.55),
                  Colors.transparent,
                ],
                stops: const [0, 0.32],
              ),
            ),
          ),
        ),
        Align(
          alignment: alignment,
          child: FractionallySizedBox(
            widthFactor: sweep,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: begin,
                  end: end,
                  colors: [
                    surface.withValues(alpha: highlightStrength),
                    Colors.white.withValues(alpha: highlightStrength * 0.9),
                    Colors.black.withValues(alpha: shadowStrength),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.18, 0.48, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _PageTurnEdgePainter(
              progress: progress,
              forward: forward,
              color: Colors.black.withValues(alpha: shadowStrength * 1.1),
            ),
          ),
        ),
      ],
    );
  }
}

class _PageTurnEdgePainter extends CustomPainter {
  _PageTurnEdgePainter({
    required this.progress,
    required this.forward,
    required this.color,
  });

  final double progress;
  final bool forward;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final edgeX = forward
        ? size.width * (1 - progress * 0.92)
        : size.width * (progress * 0.92);
    final rect = Rect.fromLTWH(
      forward ? edgeX - 28 : edgeX,
      0,
      28,
      size.height,
    );
    final paint = Paint()
      ..shader = LinearGradient(
        begin: forward ? Alignment.centerRight : Alignment.centerLeft,
        end: forward ? Alignment.centerLeft : Alignment.centerRight,
        colors: [
          color,
          color.withValues(alpha: color.a * 0.35),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _PageTurnEdgePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.forward != forward ||
        oldDelegate.color != color;
  }
}
