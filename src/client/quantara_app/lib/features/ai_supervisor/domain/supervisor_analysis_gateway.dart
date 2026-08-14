import 'supervisor_review.dart';
import 'supervisor_snapshot.dart';

/// Analysis-only boundary for Supervisor implementations.
///
/// Implementations may send the allow-listed snapshot to a local analyzer or a
/// server-side service. This interface intentionally exposes no live trading or
/// configuration mutation capability.
abstract interface class SupervisorAnalysisGateway {
  Future<SupervisorReview> review(SupervisorSnapshot snapshot);
}
