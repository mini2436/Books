import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../shared/theme/reader_theme_extension.dart';
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
      axis: Responsive.isTablet(context) || Responsive.isDesktopPlatform()
          ? Axis.vertical
          : Axis.horizontal,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usesSideNavigation =
        Responsive.isTablet(context) || Responsive.isDesktopPlatform();
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
    final destinations = <_ShellDestination>[
      const _ShellDestination(
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book,
        label: '书架',
      ),
      const _ShellDestination(
        icon: Icons.sticky_note_2_outlined,
        selectedIcon: Icons.sticky_note_2,
        label: '批注',
      ),
      if (canAccessAdmin)
        const _ShellDestination(
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings,
          label: '后台',
        ),
      const _ShellDestination(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: '我',
      ),
    ];
    final activeIndex = selectedIndex < 0 ? 0 : selectedIndex;

    if (usesSideNavigation) {
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(left: 112),
                child: navigationShell,
              ),
            ),
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: _FloatingNavigation(
                  axis: Axis.vertical,
                  destinations: destinations,
                  selectedIndex: activeIndex,
                  onDestinationSelected: (index) =>
                      _onDestinationSelected(index, visibleBranchIndexes),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _SwipeNavigationBody(
            currentIndex: activeIndex,
            destinationCount: visibleBranchIndexes.length,
            onDestinationSelected: (index) =>
                _onDestinationSelected(index, visibleBranchIndexes),
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: navigationShell,
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset + 8,
            child: _FloatingNavigation(
              axis: Axis.horizontal,
              destinations: destinations,
              selectedIndex: activeIndex,
              onDestinationSelected: (index) =>
                  _onDestinationSelected(index, visibleBranchIndexes),
            ),
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

class _ShellDestination {
  const _ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _FloatingNavigation extends StatelessWidget {
  const _FloatingNavigation({
    required this.axis,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final Axis axis;
  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(axis == Axis.horizontal ? 32 : 30);
    final surfaceOpacity = axis == Axis.horizontal
        ? (dark ? 0.38 : 0.18)
        : (dark ? 0.9 : 0.86);
    final blurSigma = axis == Axis.horizontal ? 10.0 : 18.0;
    final items = List<Widget>.generate(destinations.length, (index) {
      final destination = destinations[index];
      final item = _FloatingNavigationItem(
        axis: axis,
        destination: destination,
        selected: index == selectedIndex,
        onTap: () => onDestinationSelected(index),
      );
      return axis == Axis.horizontal ? Expanded(child: item) : item;
    });
    final arrangedItems = axis == Axis.horizontal
        ? items
        : <Widget>[
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const SizedBox(height: 6),
              items[index],
            ],
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: palette.ink.withValues(alpha: dark ? 0.26 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: palette.ink.withValues(alpha: dark ? 0.1 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.panel.withValues(alpha: surfaceOpacity),
              borderRadius: radius,
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.07)
                    : palette.ink.withValues(alpha: 0.07),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: axis == Axis.horizontal
                  ? Row(mainAxisSize: MainAxisSize.max, children: arrangedItems)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: arrangedItems,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingNavigationItem extends StatelessWidget {
  const _FloatingNavigationItem({
    required this.axis,
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final Axis axis;
  final _ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final color = selected ? palette.accent : palette.inkSecondary;
    final radius = BorderRadius.circular(24);

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: palette.accent.withValues(alpha: 0.07),
          splashColor: palette.accent.withValues(alpha: 0.1),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            constraints: BoxConstraints(
              minWidth: axis == Axis.vertical ? 68 : 60,
              minHeight: axis == Axis.horizontal ? 58 : 64,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: axis == Axis.horizontal ? 10 : 8,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? palette.accent.withValues(alpha: 0.17)
                  : Colors.transparent,
              borderRadius: radius,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    key: ValueKey(selected),
                    size: 23,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeNavigationBody extends StatefulWidget {
  const _SwipeNavigationBody({
    required this.currentIndex,
    required this.destinationCount,
    required this.onDestinationSelected,
    required this.child,
  });

  final int currentIndex;
  final int destinationCount;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  State<_SwipeNavigationBody> createState() => _SwipeNavigationBodyState();
}

class _SwipeNavigationBodyState extends State<_SwipeNavigationBody> {
  static const _distanceThreshold = 56.0;
  static const _velocityThreshold = 520.0;

  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    final enabled = !Responsive.isDesktopPlatform();
    if (!enabled) {
      return widget.child;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dragDistance = 0,
      onHorizontalDragUpdate: (details) {
        _dragDistance += details.primaryDelta ?? 0;
      },
      onHorizontalDragCancel: () => _dragDistance = 0,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final enoughDistance = _dragDistance.abs() >= _distanceThreshold;
        final enoughVelocity = velocity.abs() >= _velocityThreshold;
        if (!enoughDistance && !enoughVelocity) {
          _dragDistance = 0;
          return;
        }

        final swipeLeft = enoughDistance ? _dragDistance < 0 : velocity < 0;
        final targetIndex = widget.currentIndex + (swipeLeft ? 1 : -1);
        _dragDistance = 0;
        if (targetIndex < 0 || targetIndex >= widget.destinationCount) {
          return;
        }
        widget.onDestinationSelected(targetIndex);
      },
      child: widget.child,
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
