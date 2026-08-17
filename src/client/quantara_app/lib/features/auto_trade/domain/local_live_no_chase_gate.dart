import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../data/bitunix_order_book_top.dart';
import 'execution_quality_models.dart';

final class LocalLiveNoChaseGate {
  const LocalLiveNoChaseGate({this.policy = const NoChasePolicy()});

  final NoChasePolicy policy;

  NoChaseDecision evaluate({
    required TradeIdea idea,
    required BitunixOrderBookTop topOfBook,
    required DateTime evaluatedAtUtc,
  }) {
    if (!idea.isActionable ||
        !evaluatedAtUtc.isUtc ||
        idea.entryLower == null ||
        idea.entryUpper == null) {
      throw const FormatException('Local Live no-chase input is invalid.');
    }
    final side = switch (idea.direction) {
      TradeDirection.long => ExecutionSide.long,
      TradeDirection.short => ExecutionSide.short,
      TradeDirection.wait => throw const FormatException(
        'Local Live no-chase direction is not actionable.',
      ),
    };
    final worstAcceptablePrice = switch (side) {
      ExecutionSide.long => idea.entryUpper!,
      ExecutionSide.short => idea.entryLower!,
    };
    return policy.evaluate(
      side: side,
      executablePrice: topOfBook.executablePriceFor(side),
      worstAcceptablePrice: worstAcceptablePrice,
      evaluatedAtUtc: evaluatedAtUtc,
      validUntilUtc: idea.validUntil.toUtc(),
    );
  }
}
