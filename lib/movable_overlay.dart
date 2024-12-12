import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_in_app_pip/pip_params.dart';
import 'package:flutter_in_app_pip/pip_utils.dart';
import 'package:flutter_in_app_pip/pip_view_corner.dart';

class MovableOverlay extends StatefulWidget {
  final PiPParams pipParams;
  final bool avoidKeyboard;
  final Widget? topWidget;
  final Widget? bottomWidget;

  // this is exposed because trying to watch onTap event
  // by wrapping the top widget with a gesture detector
  // causes the tap to be lost sometimes because it
  // is competing with the drag
  final void Function()? onTapTopWidget;

  const MovableOverlay({
    Key? key,
    this.avoidKeyboard = true,
    this.topWidget,
    this.bottomWidget,
    this.onTapTopWidget,
    this.pipParams = const PiPParams(),
  }) : super(key: key);

  @override
  MovableOverlayState createState() => MovableOverlayState();
}

class MovableOverlayState extends State<MovableOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _toggleFloatingAnimationController;
  late final AnimationController _dragAnimationController;
  late PIPViewCorner _corner;
  Offset _dragOffset = Offset.zero;
  var _isDragging = false;
  var _isFloating = false;
  var _isZooming = false;
  Widget? _bottomWidgetGhost;
  Map<PIPViewCorner, Offset> _offsets = {};
  final defaultAnimationDuration = const Duration(milliseconds: 250);
  Widget? bottomChild;

  double _scaleFactor = 1.0;

  double _baseScaleFactor = 1.0;

  @override
  void initState() {
    super.initState();
    _corner = widget.pipParams.initialCorner;
    _toggleFloatingAnimationController = AnimationController(
      duration: defaultAnimationDuration,
      vsync: this,
    );
    _dragAnimationController = AnimationController(
      duration: defaultAnimationDuration,
      vsync: this,
    );
    bottomChild = widget.bottomWidget;
  }

  @override
  void dispose() {
    _toggleFloatingAnimationController.dispose();
    _dragAnimationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MovableOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isFloating) {
      _scaleFactor = 1;
      if (widget.topWidget == null || bottomChild == null) {
        _isFloating = false;
        _bottomWidgetGhost = oldWidget.bottomWidget;
        _toggleFloatingAnimationController.reverse().whenCompleteOrCancel(() {
          if (mounted) {
            setState(() => _bottomWidgetGhost = null);
          }
        });
      }
    } else {
      if (widget.topWidget != null && bottomChild != null) {
        _isFloating = true;
        _toggleFloatingAnimationController.forward();
      }
    }
  }

  void _updateCornersOffsets({
    required Size spaceSize,
    required Size widgetSize,
    required EdgeInsets windowPadding,
  }) {
    _offsets = _calculateOffsets(
      spaceSize: spaceSize,
      widgetSize: widgetSize,
      windowPadding: windowPadding,
    );
  }

  bool _isAnimating() {
    return _toggleFloatingAnimationController.isAnimating ||
        _dragAnimationController.isAnimating;
  }

  void _onPanUpdate(ScaleUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      _dragOffset = _dragOffset.translate(
        details.focalPointDelta.dx,
        details.focalPointDelta.dy,
      );
    });
  }

  void _onPanEnd(ScaleEndDetails details) {
    if (!_isDragging) return;
    if (_isZooming) {
      _handleZoomingEnd();
    } else {
      if (_offsets.isEmpty) return;
      _handleDraggingEnd(details);
    }
  }

  void _onPanStart(ScaleStartDetails details) {
    if (_isAnimating()) return;
    setState(() {
      _dragOffset = _offsets[_corner]!;
      _isDragging = true;
      _isZooming = details.pointerCount == 2;
    });
  }

  void _handleZoomingEnd() {
    _snapToNearestCorner();
    _dragAnimationController.forward().whenCompleteOrCancel(() {
      _dragAnimationController.value = 0;
      _resetDraggingState();
    });
  }

  void _handleDraggingEnd(ScaleEndDetails details) {
    final adjustedVelocity = details.velocity.pixelsPerSecond;
    final adjustedXVelocity = adjustedVelocity.dx;
    final adjustedYVelocity = adjustedVelocity.dy;

    void updateOffset() {
      double x = 0.0;
      double y = 0.0;
      if (adjustedXVelocity.abs() > adjustedYVelocity.abs()) {
        final xSimulation = FrictionSimulation(0.5, _dragOffset.dx, adjustedXVelocity);
        x = clamp(
          xSimulation.x(_dragAnimationController.value),
          _offsets[PIPViewCorner.topLeft]?.dx ?? 0.0,
          _offsets[PIPViewCorner.topRight]?.dx ?? 0.0,
        );
        y = _dragOffset.dy;
      } else {
        final ySimulation = FrictionSimulation(0.5, _dragOffset.dy, adjustedYVelocity);
        x = _dragOffset.dx;
        y = clamp(
          ySimulation.x(_dragAnimationController.value),
          _offsets[PIPViewCorner.topLeft]?.dy ?? 0.0,
          _offsets[PIPViewCorner.bottomLeft]?.dy ?? 0.0,
        );
      }
      if (_dragOffset.dx != x || _dragOffset.dy != y) {
        setState(() {
          _dragOffset = Offset(x, y);
        });
      }

      if (_dragAnimationController.isCompleted) {
        _snapToNearestCorner();
      }
    }

    _dragAnimationController
      ..addListener(updateOffset)
      ..forward(from: 0.0).whenCompleteOrCancel(() {
        _resetDraggingState();
        _dragAnimationController.removeListener(updateOffset);
      });
  }

  void _snapToNearestCorner() {
    final nearestCorner = _calculateNearestCorner(
      offset: _dragOffset,
      offsets: _offsets,
    );
    setState(() {
      _corner = nearestCorner;
      _dragOffset = _offsets[_corner]!;
    });
  }

  void _resetDraggingState() {
    setState(() {
      _dragOffset = Offset.zero;
      _isDragging = false;
      _isZooming = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    var windowPadding = mediaQuery.padding;
    if (widget.avoidKeyboard) {
      windowPadding += mediaQuery.viewInsets;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomWidget = bottomChild ?? _bottomWidgetGhost;
        
        double floatingWidth = 0;
        double floatingHeight = 0;

        if (widget.topWidget != null) {
          floatingWidth = widget.pipParams.pipWindowWidth * _scaleFactor;
          floatingHeight = widget.pipParams.pipWindowHeight * _scaleFactor;
        }

        final floatingWidgetSize = Size(floatingWidth, floatingHeight);
        final fullWidgetSize = Size(constraints.maxWidth, constraints.maxHeight);

        _updateCornersOffsets(
          spaceSize: fullWidgetSize,
          widgetSize: floatingWidgetSize,
          windowPadding: windowPadding,
        );

        final calculatedOffset = _offsets[_corner];

        return Stack(
          children: <Widget>[
            if (bottomWidget != null) Center(child: bottomWidget),
            if (widget.topWidget != null)
              AnimatedBuilder(
                animation: Listenable.merge([
                  _toggleFloatingAnimationController,
                  _dragAnimationController,
                ]),
                builder: (context, child) {
                  final animationCurve = CurveTween(
                    curve: Curves.easeInOutQuad,
                  );
                  final dragAnimationValue = animationCurve.transform(
                    _dragAnimationController.value,
                  );
                  final toggleFloatingAnimationValue = animationCurve.transform(
                    _toggleFloatingAnimationController.value,
                  );

                  final floatingOffset = _isDragging
                      ? _dragOffset
                      : Offset.lerp(
                          _dragOffset,
                          calculatedOffset,
                          _dragAnimationController.isAnimating
                              ? dragAnimationValue
                              : toggleFloatingAnimationValue,
                        )!;
                  final width = fullWidgetSize.width +
                      (floatingWidgetSize.width - fullWidgetSize.width) *
                          toggleFloatingAnimationValue;
                  final height = fullWidgetSize.height +
                      (floatingWidgetSize.height - fullWidgetSize.height) *
                          toggleFloatingAnimationValue;
                  return Positioned(
                    left: floatingOffset.dx,
                    top: floatingOffset.dy,
                    child: GestureDetector(
                      onScaleStart: _isFloating ? _onScaleStart : null,
                      onScaleEnd: _isFloating ? _onScaleEnd : null,
                      onScaleUpdate: _isFloating ? _onScaleUpdate : null,
                      onTap: widget.onTapTopWidget,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: child,
                      ),
                    ),
                  );
                },
                child: widget.topWidget,
              ),
          ],
        );
      },
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (widget.pipParams.movable) {
      _onPanStart(details);
    }
    if (widget.pipParams.resizable) {
      _baseScaleFactor = _scaleFactor;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (widget.pipParams.movable) {
      _onPanEnd(details);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (widget.pipParams.movable) {
      _onPanUpdate(details);
    }
    if (widget.pipParams.resizable == false || details.scale == 1.0) {
      return;
    }
    if (details.scale * _baseScaleFactor * widget.pipParams.pipWindowWidth >
        widget.pipParams.maxSize.width) {
      return;
    }
    if (details.scale * _baseScaleFactor * widget.pipParams.pipWindowWidth <
        widget.pipParams.minSize.width) {
      return;
    }
    if (details.scale * _baseScaleFactor * widget.pipParams.pipWindowHeight >
        widget.pipParams.maxSize.height) {
      return;
    }
    if (details.scale * _baseScaleFactor * widget.pipParams.pipWindowHeight <
        widget.pipParams.minSize.height) {
      return;
    }
    _scaleFactor = (_baseScaleFactor * details.scale);
    setState(() {});
  }

  Map<PIPViewCorner, Offset> _calculateOffsets({
    required Size spaceSize,
    required Size widgetSize,
    required EdgeInsets windowPadding,
  }) {
    Offset getOffsetForCorner(PIPViewCorner corner) {
      final left = widget.pipParams.leftSpace + windowPadding.left;
      final top = widget.pipParams.topSpace + windowPadding.top;
      final right = spaceSize.width -
          widgetSize.width -
          windowPadding.right -
          widget.pipParams.rightSpace;
      final bottom = spaceSize.height -
          widgetSize.height -
          windowPadding.bottom -
          widget.pipParams.bottomSpace;

      switch (corner) {
        case PIPViewCorner.topLeft:
          return Offset(left, top);
        case PIPViewCorner.topRight:
          return Offset(right, top);
        case PIPViewCorner.bottomLeft:
          return Offset(left, bottom);
        case PIPViewCorner.bottomRight:
          return Offset(right, bottom);
        default:
          throw UnimplementedError();
      }
    }

    const corners = PIPViewCorner.values;
    final Map<PIPViewCorner, Offset> offsets = {};
    for (final corner in corners) {
      offsets[corner] = getOffsetForCorner(corner);
    }

    return offsets;
  }
}

class _CornerDistance {
  final PIPViewCorner corner;
  final double distance;

  _CornerDistance({
    required this.corner,
    required this.distance,
  });
}

PIPViewCorner _calculateNearestCorner({
  required Offset offset,
  required Map<PIPViewCorner, Offset> offsets,
}) {
  _CornerDistance calculateDistance(PIPViewCorner corner) {
    final distance = offsets[corner]!
        .translate(
          -offset.dx,
          -offset.dy,
        )
        .distanceSquared;
    return _CornerDistance(
      corner: corner,
      distance: distance,
    );
  }

  final distances = PIPViewCorner.values.map(calculateDistance).toList();

  distances.sort((cd0, cd1) => cd0.distance.compareTo(cd1.distance));

  return distances.first.corner;
}
