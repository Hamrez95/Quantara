import 'package:flutter/foundation.dart';

import '../data/durable_strategy_robot_binding_store.dart';
import '../data/strategy_registry.dart';
import '../domain/owner_alpha_models.dart';
import 'strategy_robot_binding.dart';

/// Owns the user's selected evaluated strategy identity for Guarded Auto.
///
/// Selection and restore are configuration-only. This controller never starts
/// Local Live, submits an order, or grants exchange authority. A binding is
/// exposed as resolved only when its immutable identity still resolves exactly
/// against the supplied historical registry.
final class StrategyRobotBindingController extends ChangeNotifier {
  StrategyRobotBindingController({
    required this._store,
    required this._registry,
  });

  final DurableStrategyRobotBindingStore _store;
  final StrategyRegistry _registry;

  StrategyRobotBinding? _binding;
  StrategyResolution? _resolution;
  bool _initialized = false;
  bool _busy = false;

  bool get initialized => _initialized;
  bool get busy => _busy;
  StrategyRobotBinding? get binding => _binding;
  StrategyResolution? get resolution => _resolution;
  bool get hasResolvableBinding => _binding != null && _resolution != null;

  Future<void> initialize() async {
    if (_initialized || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      final restored = await _store.load();
      final resolved = restored?.resolveExact(_registry);
      if (restored != null && resolved == null) {
        // Fail closed on catalog drift/corruption: keep the persisted evidence
        // intact for diagnostics, but do not expose it as an armed selection.
        _binding = restored;
        _resolution = null;
      } else {
        _binding = restored;
        _resolution = resolved;
      }
      _initialized = true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Selects a tested setup for the robot without activating execution.
  ///
  /// Returns false when the evaluated idea is incomplete or no longer resolves
  /// to the exact immutable registry snapshot that produced it.
  Future<bool> useInRobot({
    required String evaluationRunId,
    required TradeIdea idea,
  }) async {
    if (_busy) return false;
    final candidate = StrategyRobotBinding.fromEvaluatedIdea(
      evaluationRunId: evaluationRunId,
      idea: idea,
    );
    final resolved = candidate?.resolveExact(_registry);
    if (candidate == null || resolved == null) return false;

    _busy = true;
    notifyListeners();
    try {
      await _store.save(candidate);
      _binding = candidate;
      _resolution = resolved;
      _initialized = true;
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _store.clear();
      _binding = null;
      _resolution = null;
      _initialized = true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
