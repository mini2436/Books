import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:private_reader_mobile/shared/localization/localized_text.dart';
import 'package:private_reader_mobile/shared/localization/app_localizations.dart';

import '../features/auth/auth_controller.dart';
import '../shared/theme/glass_theme.dart';
import '../shared/theme/reader_theme_extension.dart';
import '../shared/utils/responsive.dart';
import '../shared/widgets/glass_surface.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static Widget buildBranchContainer(
    BuildContext context,
    StatefulNavigationShell navigationShell,
    List<Widget> children,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final canAccessAdmin = ref.watch(
          authControllerProvider.select(
            (auth) => auth.user?.canAccessAdmin ?? false,
          ),
        );
        final isOfflineGuest = ref.watch(
          authControllerProvider.select((auth) => auth.isOfflineGuest),
        );
        final visibleBranchIndexes = isOfflineGuest
            ? const [0, 3]
            : canAccessAdmin
            ? const [0, 1, 2, 3]
            : const [0, 1, 3];
        return _AnimatedBranchContainer(
          currentIndex: navigationShell.currentIndex,
          visibleIndexes: visibleBranchIndexes,
          axis: Responsive.isTablet(context) || Responsive.isDesktopPlatform()
              ? Axis.vertical
              : Axis.horizontal,
          interactive:
              Responsive.platformLayout(context) == AppPlatformLayout.phone,
          onIndexSelected: (index) => navigationShell.goBranch(index),
          children: children,
        );
      },
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
    final isOfflineGuest = ref.watch(
      authControllerProvider.select((auth) => auth.isOfflineGuest),
    );
    final visibleBranchIndexes = isOfflineGuest
        ? const [0, 3]
        : canAccessAdmin
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
      if (!isOfflineGuest)
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
          MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: navigationShell,
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
    final radius = BorderRadius.circular(axis == Axis.horizontal ? 32 : 30);
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

    return GlassSurface(
      level: GlassSurfaceLevel.floating,
      enableLiquidGlass: true,
      borderRadius: radius,
      padding: const EdgeInsets.all(6),
      child: axis == Axis.horizontal
          ? Row(mainAxisSize: MainAxisSize.max, children: arrangedItems)
          : Column(mainAxisSize: MainAxisSize.min, children: arrangedItems),
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
      label: context.tr(destination.label),
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

class _AnimatedBranchContainer extends StatefulWidget {
  const _AnimatedBranchContainer({
    required this.currentIndex,
    required this.visibleIndexes,
    required this.axis,
    required this.interactive,
    required this.onIndexSelected,
    required this.children,
  });

  final int currentIndex;
  final List<int> visibleIndexes;
  final Axis axis;
  final bool interactive;
  final ValueChanged<int> onIndexSelected;
  final List<Widget> children;

  @override
  State<_AnimatedBranchContainer> createState() =>
      _AnimatedBranchContainerState();
}

class _AnimatedBranchContainerState extends State<_AnimatedBranchContainer>
    with TickerProviderStateMixin {
  static const _commitProgress = 0.22;
  static const _commitVelocity = 650.0;

  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  late final AnimationController _dragController;
  Animation<double>? _dragAnimation;
  late int _previousIndex;
  bool _forward = true;
  bool _skipNextTransition = false;
  double _dragExtent = 1;
  double _rawDragDistance = 0;
  double _dragOffset = 0;
  int? _dragTargetIndex;

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
    _dragController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final dragAnimation = _dragAnimation;
          if (dragAnimation == null || !mounted) {
            return;
          }
          setState(() => _dragOffset = dragAnimation.value);
        });
  }

  @override
  void didUpdateWidget(covariant _AnimatedBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) {
      return;
    }
    if (_skipNextTransition && widget.currentIndex == _dragTargetIndex) {
      _skipNextTransition = false;
      _previousIndex = widget.currentIndex;
      _controller.stop();
      _dragController.stop();
      _dragAnimation = null;
      _rawDragDistance = 0;
      _dragOffset = 0;
      _dragTargetIndex = null;
      return;
    }
    _dragController.stop();
    _dragAnimation = null;
    _rawDragDistance = 0;
    _dragOffset = 0;
    _dragTargetIndex = null;
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
    _dragController.dispose();
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
          if (extent.isFinite && extent > 0) {
            _dragExtent = extent;
          }
          final dragging =
              widget.interactive &&
              (_dragOffset != 0 || _dragTargetIndex != null);

          final foregroundIndexes = <int>[
            if (dragging && _dragTargetIndex != null) _dragTargetIndex!,
            if (!dragging &&
                _controller.isAnimating &&
                _previousIndex != widget.currentIndex)
              _previousIndex,
            widget.currentIndex,
          ];
          final paintOrder = <int>[
            ...foregroundIndexes,
            ...List<int>.generate(
              widget.children.length,
              (index) => index,
            ).where((index) => !foregroundIndexes.contains(index)),
          ];

          final stackItems = paintOrder.map((index) {
            final isVisible = dragging
                ? index == widget.currentIndex || index == _dragTargetIndex
                : index == widget.currentIndex ||
                      (_controller.isAnimating && index == _previousIndex);
            return _BranchContainer(
              isActive: isVisible,
              child: IgnorePointer(
                ignoring: index != widget.currentIndex,
                child: AnimatedBuilder(
                  animation: _animation,
                  child: widget.children[index],
                  builder: (context, child) {
                    final transition = dragging
                        ? _dragTransitionFor(index: index, extent: extent)
                        : _transitionFor(index: index, distance: distance);
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
              ),
            );
          }).toList();

          final content = Stack(fit: StackFit.expand, children: stackItems);
          if (!widget.interactive) {
            return content;
          }
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _handleDragStart,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragCancel: _handleDragCancel,
            onHorizontalDragEnd: _handleDragEnd,
            child: content,
          );
        },
      ),
    );
  }

  void _handleDragStart(DragStartDetails details) {
    _controller.stop();
    _dragController.stop();
    _dragAnimation = null;
    setState(() {
      _rawDragDistance = 0;
      _dragOffset = 0;
      _dragTargetIndex = null;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta == 0 || _dragExtent <= 0) {
      return;
    }
    setState(() {
      _rawDragDistance += delta;
      _dragTargetIndex = _targetForDirection(_rawDragDistance.sign);
      final clamped = _rawDragDistance.clamp(-_dragExtent, _dragExtent);
      _dragOffset = _dragTargetIndex == null ? clamped * 0.18 : clamped;
    });
  }

  void _handleDragCancel() => _settleDrag(0);

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final direction = _rawDragDistance == 0
        ? velocity.sign
        : _rawDragDistance.sign;
    final targetIndex = _targetForDirection(direction);
    final enoughDistance = _dragOffset.abs() / _dragExtent >= _commitProgress;
    final enoughVelocity =
        velocity.abs() >= _commitVelocity &&
        (velocity.sign == direction || _rawDragDistance.abs() < 12);
    if (targetIndex != null && (enoughDistance || enoughVelocity)) {
      _dragTargetIndex = targetIndex;
      _settleDrag(direction * _dragExtent, commitIndex: targetIndex);
      return;
    }
    _settleDrag(0);
  }

  void _settleDrag(double target, {int? commitIndex}) {
    _dragController.stop();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final distance = (target - _dragOffset).abs();
    _dragController.duration = reduceMotion
        ? Duration.zero
        : Duration(
            milliseconds: (140 + 100 * (distance / _dragExtent)).round().clamp(
              140,
              240,
            ),
          );
    _dragAnimation = Tween<double>(begin: _dragOffset, end: target).animate(
      CurvedAnimation(parent: _dragController, curve: Curves.easeOutCubic),
    );
    _dragController.forward(from: 0).whenComplete(() {
      if (!mounted) {
        return;
      }
      if (commitIndex != null) {
        _skipNextTransition = true;
        widget.onIndexSelected(commitIndex);
        return;
      }
      setState(() {
        _dragAnimation = null;
        _rawDragDistance = 0;
        _dragOffset = 0;
        _dragTargetIndex = null;
      });
    });
  }

  int? _targetForDirection(double direction) {
    if (direction == 0) {
      return null;
    }
    final currentPosition = widget.visibleIndexes.indexOf(widget.currentIndex);
    if (currentPosition < 0) {
      return null;
    }
    final targetPosition = currentPosition + (direction < 0 ? 1 : -1);
    if (targetPosition < 0 || targetPosition >= widget.visibleIndexes.length) {
      return null;
    }
    return widget.visibleIndexes[targetPosition];
  }

  _BranchTransition? _dragTransitionFor({
    required int index,
    required double extent,
  }) {
    if (index == widget.currentIndex) {
      final progress = (_dragOffset.abs() / extent).clamp(0.0, 1.0);
      return _BranchTransition(
        offset: Offset(_dragOffset, 0),
        opacity: 1 - progress * 0.08,
      );
    }
    if (index == _dragTargetIndex) {
      final startsOnRight = _dragOffset < 0;
      final targetOffset = _dragOffset + (startsOnRight ? extent : -extent);
      final progress = (_dragOffset.abs() / extent).clamp(0.0, 1.0);
      return _BranchTransition(
        offset: Offset(targetOffset, 0),
        opacity: 0.9 + progress * 0.1,
      );
    }
    return null;
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
