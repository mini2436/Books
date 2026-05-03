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
      axis: Responsive.isTablet(context) ? Axis.vertical : Axis.horizontal,
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
    required this.axis,
    required this.children,
  });

  final int currentIndex;
  final Axis axis;
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
      duration: const Duration(milliseconds: 280),
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
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final extent = widget.axis == Axis.horizontal
              ? constraints.maxWidth
              : constraints.maxHeight;
          final distance = extent.isFinite && extent > 0 ? extent * 0.12 : 48.0;

          final paintOrder = <int>[
            if (_controller.isAnimating &&
                _previousIndex != widget.currentIndex)
              _previousIndex,
            widget.currentIndex,
            ...List<int>.generate(
              widget.children.length,
              (index) => index,
            ).where(
              (index) =>
                  index != widget.currentIndex && index != _previousIndex,
            ),
          ];

          final stackItems = paintOrder.map((index) {
            final isVisible =
                index == widget.currentIndex ||
                (_controller.isAnimating && index == _previousIndex);
            return _BranchContainer(
              isActive: isVisible,
              child: AnimatedBuilder(
                animation: _animation,
                child: widget.children[index],
                builder: (context, child) {
                  final transition = _transitionFor(
                    index: index,
                    distance: distance,
                  );
                  if (transition == null) {
                    return child!;
                  }
                  return Opacity(
                    opacity: transition.opacity,
                    child: Transform.translate(
                      offset: transition.offset,
                      child: child,
                    ),
                  );
                },
              ),
            );
          }).toList();

          return Stack(fit: StackFit.expand, children: stackItems);
        },
      ),
    );
  }

  _BranchTransition? _transitionFor({
    required int index,
    required double distance,
  }) {
    if (!_controller.isAnimating) {
      return index == widget.currentIndex
          ? const _BranchTransition(offset: Offset.zero, opacity: 1)
          : null;
    }

    final progress = _animation.value;
    final direction = _forward ? 1.0 : -1.0;
    final horizontal = widget.axis == Axis.horizontal;

    if (index == widget.currentIndex) {
      final incomingFactor = (1 - progress) * direction;
      return _BranchTransition(
        offset: horizontal
            ? Offset(distance * incomingFactor, 0)
            : Offset(0, distance * incomingFactor),
        opacity: 0.76 + (progress * 0.24),
      );
    }

    if (index == _previousIndex) {
      final outgoingFactor = -progress * direction;
      return _BranchTransition(
        offset: horizontal
            ? Offset(distance * outgoingFactor, 0)
            : Offset(0, distance * outgoingFactor),
        opacity: 1 - (progress * 0.32),
      );
    }

    return null;
  }
}

class _BranchTransition {
  const _BranchTransition({required this.offset, required this.opacity});

  final Offset offset;
  final double opacity;
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
