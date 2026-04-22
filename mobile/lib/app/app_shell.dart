import 'dart:math' as math;

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
                NavigationRailDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: Text('书架'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.sticky_note_2_outlined),
                  selectedIcon: Icon(Icons.sticky_note_2),
                  label: Text('批注'),
                ),
                if (canAccessAdmin)
                  NavigationRailDestination(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    selectedIcon: Icon(Icons.admin_panel_settings),
                    label: Text('后台'),
                  ),
                NavigationRailDestination(
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
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            selectedIcon: Icon(Icons.sticky_note_2),
            label: '批注',
          ),
          if (canAccessAdmin)
            NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings),
              label: '后台',
            ),
          NavigationDestination(
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
  int? _previousIndex;
  late int _currentIndex;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _previousIndex = null;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant _AnimatedBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex == _currentIndex) {
      return;
    }
    _forward = widget.currentIndex > _currentIndex;
    _previousIndex = _currentIndex;
    _currentIndex = widget.currentIndex;
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: List.generate(widget.children.length, (index) {
            final isCurrent = index == _currentIndex;
            final isPrevious =
                _previousIndex != null && index == _previousIndex;
            final isAnimating =
                _controller.isAnimating && (isCurrent || isPrevious);
            final shouldShow = isCurrent || isPrevious;

            return Offstage(
              offstage: !shouldShow,
              child: TickerMode(
                enabled: shouldShow,
                child: IgnorePointer(
                  ignoring: !isCurrent,
                  child: Transform(
                    alignment: _forward
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    transform: _buildTransform(
                      width: MediaQuery.sizeOf(context).width,
                      isCurrent: isCurrent,
                      isPrevious: isPrevious,
                      animationValue: _animation.value,
                      isAnimating: isAnimating,
                    ),
                    child: Opacity(
                      opacity: _opacityFor(
                        isCurrent: isCurrent,
                        isPrevious: isPrevious,
                        animationValue: _animation.value,
                        isAnimating: isAnimating,
                      ),
                      child: widget.children[index],
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Matrix4 _buildTransform({
    required double width,
    required bool isCurrent,
    required bool isPrevious,
    required double animationValue,
    required bool isAnimating,
  }) {
    final progress = animationValue;
    final direction = _forward ? 1.0 : -1.0;
    final base = Matrix4.identity()..setEntry(3, 2, 0.0012);

    if (!isAnimating) {
      return base;
    }

    if (isCurrent) {
      final dx = (1 - progress) * width * 0.15 * direction;
      final angle = (1 - progress) * 0.09 * direction;
      return base
        ..translateByDouble(dx, 0, 0, 1)
        ..rotateY(-angle)
        ..scaleByDouble(
          0.985 + (progress * 0.015),
          0.985 + (progress * 0.015),
          1,
          1,
        );
    }

    if (isPrevious) {
      final dx = progress * width * -0.08 * direction;
      final angle = progress * 0.05 * direction;
      return base
        ..translateByDouble(dx, 0, 0, 1)
        ..rotateY(angle)
        ..scaleByDouble(
          1 - math.min(progress * 0.02, 0.02),
          1 - math.min(progress * 0.02, 0.02),
          1,
          1,
        );
    }

    return base;
  }

  double _opacityFor({
    required bool isCurrent,
    required bool isPrevious,
    required double animationValue,
    required bool isAnimating,
  }) {
    if (!isAnimating) {
      return isCurrent ? 1 : 0;
    }
    if (isCurrent) {
      return 0.72 + (animationValue * 0.28);
    }
    if (isPrevious) {
      return 1 - (animationValue * 0.32);
    }
    return 0;
  }
}
