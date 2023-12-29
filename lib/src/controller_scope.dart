import 'package:control/src/controller.dart';
import 'package:control/src/state_controller.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Extension methods for [BuildContext]
/// to simplify the use of [ControllerScope].
extension ControllerScopeBuildContextExtension on BuildContext {
  /// The state from the closest instance of this class
  /// that encloses the given context.
  /// e.g. `context.controllerOf<MyStateController>()`
  C controllerOf<C extends IController>({bool listen = false}) =>
      ControllerScope.of<C>(this, listen: listen);
}

/// {@template controller_scope}
/// Dependency injection of [Controller]s.
/// {@endtemplate}
@experimental
class ControllerScope<C extends IController> extends InheritedWidget {
  /// {@macro controller_scope}
  ControllerScope(
    C Function() create, {
    Widget? child,
    bool lazy = true,
    super.key,
  })  : _dependency = _ControllerDependency$Create<C>(
          create: create,
          lazy: lazy,
        ),
        super(child: child ?? const SizedBox.shrink());

  /// {@macro controller_scope}
  ControllerScope.value(
    C controller, {
    Widget? child,
    super.key,
  })  : _dependency = _ControllerDependency$Value<C>(
          controller: controller,
        ),
        super(child: child ?? const SizedBox.shrink());

  final _ControllerDependency<C> _dependency;

  /// The state from the closest instance of this class
  /// that encloses the given context, if any.
  /// e.g. `ControllerScope.maybeOf<MyStateController>(context)`.
  static C? maybeOf<C extends IController>(BuildContext context,
      {bool listen = false}) {
    final element =
        context.getElementForInheritedWidgetOfExactType<ControllerScope<C>>();
    if (listen && element != null) context.dependOnInheritedElement(element);
    return element is ControllerScope$Element<C> ? element.controller : null;
  }

  static Never _notFoundInheritedWidgetOfExactType() => throw ArgumentError(
        'Out of scope, not found inherited widget '
            'a ControllerScope of the exact type',
        'out_of_scope',
      );

  /// The state from the closest instance of this class
  /// that encloses the given context.
  /// e.g. `ControllerScope.of<MyStateController>(context)`
  static C of<C extends IController>(BuildContext context,
          {bool listen = false}) =>
      maybeOf<C>(context, listen: listen) ??
      _notFoundInheritedWidgetOfExactType();

  @override
  bool updateShouldNotify(covariant ControllerScope oldWidget) =>
      _dependency != oldWidget._dependency;

  @override
  InheritedElement createElement() => ControllerScope$Element<C>(this);
}

/// {@nodoc}
@internal
final class ControllerScope$Element<C extends IController>
    extends InheritedElement {
  /// {@nodoc}
  ControllerScope$Element(ControllerScope<C> widget) : super(widget);

  @nonVirtual
  _ControllerDependency<C> get _dependency =>
      (widget as ControllerScope<C>)._dependency;

  @nonVirtual
  C? _controller;

  /// Use this getter to initialize the controller.
  /// Use [_controller] instead of [controller] to avoid initialization.
  @nonVirtual
  C get controller => _controller ??= _initController();

  /// Last known state of the controller.
  @nonVirtual
  Object? _state;

  @nonVirtual
  bool _dirty = false;

  @nonVirtual
  bool _subscribed = false;

  @nonVirtual
  C _initController() {
    if (_controller != null) {
      assert(false, 'Controller already initialized');
      return _controller!;
    }
    final c = switch (_dependency) {
      _ControllerDependency$Create<C> d => d.create(),
      _ControllerDependency$Value<C> d => d.controller,
    };
    return c;
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    if (_controller == null) {
      switch (_dependency) {
        case _ControllerDependency$Create<C> d:
          if (!d.lazy) _controller = d.create();
          break;
        case _ControllerDependency$Value<C> d:
          _controller = d.controller;
          break;
      }
    }
    super.mount(parent, newSlot);
  }

  @override
  @mustCallSuper
  void update(covariant ControllerScope<C> newWidget) {
    final oldDependency = _dependency;
    final newDependency = newWidget._dependency;
    if (!identical(oldDependency, newDependency)) {
      switch (newDependency) {
        case _ControllerDependency$Create<C> d:
          assert(
            oldDependency is _ControllerDependency$Create<C>,
            'Cannot change scope type',
          );
          if (_controller == null && (!d.lazy || _subscribed)) {
            _controller = d.create();
          }
        case _ControllerDependency$Value<C> d:
          assert(
            oldDependency is _ControllerDependency$Value<C>,
            'Cannot change scope type',
          );
          final newController = d.controller;
          if (!identical(_controller, newController)) {
            _controller?.removeListener(_handleUpdate);
            _controller = newController;
          }
      }
      // Re-subscribe if necessary
      if (_subscribed) _controller?.addListener(_handleUpdate);
    }
    super.update(newWidget);
  }

  @mustCallSuper
  void _handleUpdate() {
    final newState = switch (_controller) {
      StateController<Object?> c => c.state,
      ValueListenable<Object?> c => c.value,
      _ => null,
    };
    if (identical(_state, newState)) return; // Do nothing if state is the same
    _state = newState;
    _dirty = true;
    markNeedsBuild();
  }

  @override
  @mustCallSuper
  void updateDependencies(Element dependent, Object? aspect) {
    if (!_subscribed) {
      _subscribed = true;
      controller.addListener(_handleUpdate); // init and subscribe
    }
    super.updateDependencies(dependent, aspect);
  }

  @override
  @mustCallSuper
  void notifyClients(covariant ControllerScope<C> oldWidget) {
    super.notifyClients(oldWidget);
    _dirty = false;
  }

  @override
  @mustCallSuper
  void unmount() {
    _controller?.removeListener(_handleUpdate);
    _subscribed = false;
    // Dispose controller if it was created by this scope
    if (_dependency is _ControllerDependency$Create<C>) _controller?.dispose();
    super.unmount();
  }

  @override
  Widget build() {
    if (_dirty && _subscribed) notifyClients(widget as ControllerScope<C>);
    return super.build();
  }
}

/// {@nodoc}
@immutable
sealed class _ControllerDependency<Controller extends IController> {
  const _ControllerDependency();
}

/// {@nodoc}
final class _ControllerDependency$Create<Controller extends IController>
    extends _ControllerDependency<Controller> {
  const _ControllerDependency$Create(
      {required this.create, required this.lazy});

  final Controller Function() create;

  final bool lazy;

  @override
  int get hashCode => create.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _ControllerDependency$Create;
}

/// {@nodoc}
final class _ControllerDependency$Value<Controller extends IController>
    extends _ControllerDependency<Controller> {
  const _ControllerDependency$Value({required this.controller});

  final Controller controller;

  @override
  int get hashCode => controller.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ControllerDependency$Value &&
          identical(controller, other.controller);
}
