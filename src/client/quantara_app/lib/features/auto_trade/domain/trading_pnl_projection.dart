enum TradingPnlSource {
  bitunixPendingPosition,
  bitunixTradeHistory,
  bitunixPositionHistory,
  localLiveSession,
  journal,
}

enum TradingPnlScope { position, account, session, journal }

enum TradingPnlState { confirmed, stale, unavailable, unverified }

final class TradingPnlMetric {
  const TradingPnlMetric({
    required this.value,
    required this.currency,
    required this.source,
    required this.scope,
    required this.asOf,
    required this.state,
    this.warning,
  });

  factory TradingPnlMetric.confirmed({
    required double value,
    required String currency,
    required TradingPnlSource source,
    required TradingPnlScope scope,
    required DateTime asOf,
  }) => TradingPnlMetric(
    value: value,
    currency: currency,
    source: source,
    scope: scope,
    asOf: asOf.toUtc(),
    state: TradingPnlState.confirmed,
  );

  factory TradingPnlMetric.unavailable({
    required String currency,
    required TradingPnlSource source,
    required TradingPnlScope scope,
    required DateTime asOf,
    String? warning,
  }) => TradingPnlMetric(
    value: null,
    currency: currency,
    source: source,
    scope: scope,
    asOf: asOf.toUtc(),
    state: TradingPnlState.unavailable,
    warning: warning,
  );

  final double? value;
  final String currency;
  final TradingPnlSource source;
  final TradingPnlScope scope;
  final DateTime asOf;
  final TradingPnlState state;
  final String? warning;

  bool get isAvailable => value != null && state != TradingPnlState.unverified;
  bool get isFinal => isAvailable && state == TradingPnlState.confirmed;

  TradingPnlMetric withState(TradingPnlState next, {String? warning}) =>
      TradingPnlMetric(
        value: value,
        currency: currency,
        source: source,
        scope: scope,
        asOf: asOf,
        state: next,
        warning: warning ?? this.warning,
      );

  Map<String, Object?> toJson() => {
    'value': value,
    'currency': currency,
    'source': source.name,
    'scope': scope.name,
    'asOf': asOf.toUtc().toIso8601String(),
    'state': state.name,
    'warning': warning,
  };

  factory TradingPnlMetric.fromJson(Map<String, Object?> json) =>
      TradingPnlMetric(
        value: (json['value'] as num?)?.toDouble(),
        currency: json['currency']?.toString() ?? 'USDT',
        source: TradingPnlSource.values.firstWhere(
          (item) => item.name == json['source'],
          orElse: () => TradingPnlSource.bitunixTradeHistory,
        ),
        scope: TradingPnlScope.values.firstWhere(
          (item) => item.name == json['scope'],
          orElse: () => TradingPnlScope.account,
        ),
        asOf:
            DateTime.tryParse(json['asOf']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        state: TradingPnlState.values.firstWhere(
          (item) => item.name == json['state'],
          orElse: () => TradingPnlState.unavailable,
        ),
        warning: json['warning']?.toString(),
      );
}

final class ExchangePnlFill {
  const ExchangePnlFill({
    required this.tradeId,
    required this.orderId,
    required this.positionId,
    required this.symbol,
    required this.quantity,
    required this.price,
    required this.realizedPnl,
    required this.fee,
    required this.reduceOnly,
    required this.occurredAt,
    this.clientId = '',
    this.side = '',
  });

  final String tradeId;
  final String orderId;
  final String positionId;
  final String symbol;
  final double quantity;
  final double price;
  final double realizedPnl;
  final double fee;
  final bool reduceOnly;
  final DateTime occurredAt;
  final String clientId;
  final String side;

  String get positionKey => positionId.trim().isNotEmpty
      ? positionId.trim()
      : 'symbol:${symbol.trim().toUpperCase()}';

  bool sameEconomicEvent(ExchangePnlFill other) =>
      tradeId == other.tradeId &&
      orderId == other.orderId &&
      positionKey == other.positionKey &&
      symbol == other.symbol &&
      quantity == other.quantity &&
      price == other.price &&
      realizedPnl == other.realizedPnl &&
      fee == other.fee &&
      reduceOnly == other.reduceOnly &&
      occurredAt.toUtc() == other.occurredAt.toUtc();

  Map<String, Object?> toJson() => {
    'tradeId': tradeId,
    'orderId': orderId,
    'positionId': positionId,
    'symbol': symbol,
    'quantity': quantity,
    'price': price,
    'realizedPnl': realizedPnl,
    'fee': fee,
    'reduceOnly': reduceOnly,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'clientId': clientId,
    'side': side,
  };

  factory ExchangePnlFill.fromJson(Map<String, Object?> json) =>
      ExchangePnlFill(
        tradeId: json['tradeId']?.toString() ?? '',
        orderId: json['orderId']?.toString() ?? '',
        positionId: json['positionId']?.toString() ?? '',
        symbol: json['symbol']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        realizedPnl: (json['realizedPnl'] as num?)?.toDouble() ?? 0,
        fee: (json['fee'] as num?)?.toDouble() ?? 0,
        reduceOnly: json['reduceOnly'] == true,
        occurredAt:
            DateTime.tryParse(json['occurredAt']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        clientId: json['clientId']?.toString() ?? '',
        side: json['side']?.toString() ?? '',
      );
}

final class ExchangePositionSettlement {
  const ExchangePositionSettlement({
    required this.positionId,
    required this.symbol,
    required this.funding,
    required this.closedAt,
    this.openedAt,
    this.realizedPnl,
    this.fee,
  });

  final String positionId;
  final String symbol;
  final double? funding;
  final DateTime closedAt;
  final DateTime? openedAt;
  final double? realizedPnl;
  final double? fee;

  String get positionKey => positionId.trim().isNotEmpty
      ? positionId.trim()
      : 'symbol:${symbol.trim().toUpperCase()}';

  bool sameEconomicEvent(ExchangePositionSettlement other) =>
      positionKey == other.positionKey &&
      symbol == other.symbol &&
      funding == other.funding &&
      realizedPnl == other.realizedPnl &&
      fee == other.fee &&
      openedAt?.toUtc() == other.openedAt?.toUtc() &&
      closedAt.toUtc() == other.closedAt.toUtc();

  Map<String, Object?> toJson() => {
    'positionId': positionId,
    'symbol': symbol,
    'funding': funding,
    'openedAt': openedAt?.toUtc().toIso8601String(),
    'closedAt': closedAt.toUtc().toIso8601String(),
    'realizedPnl': realizedPnl,
    'fee': fee,
  };

  factory ExchangePositionSettlement.fromJson(Map<String, Object?> json) =>
      ExchangePositionSettlement(
        positionId: json['positionId']?.toString() ?? '',
        symbol: json['symbol']?.toString() ?? '',
        funding: (json['funding'] as num?)?.toDouble(),
        openedAt: DateTime.tryParse(
          json['openedAt']?.toString() ?? '',
        )?.toUtc(),
        closedAt:
            DateTime.tryParse(json['closedAt']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        realizedPnl: (json['realizedPnl'] as num?)?.toDouble(),
        fee: (json['fee'] as num?)?.toDouble(),
      );
}

final class ExchangeUnrealizedPnl {
  const ExchangeUnrealizedPnl({
    required this.positionId,
    required this.symbol,
    required this.value,
    this.realizedPnl,
    this.fee,
    this.funding,
    this.openedAt,
  });

  final String positionId;
  final String symbol;
  final double value;
  final double? realizedPnl;
  final double? fee;
  final double? funding;
  final DateTime? openedAt;

  Map<String, Object?> toJson() => {
    'positionId': positionId,
    'symbol': symbol,
    'value': value,
    'realizedPnl': realizedPnl,
    'fee': fee,
    'funding': funding,
    'openedAt': openedAt?.toUtc().toIso8601String(),
  };

  factory ExchangeUnrealizedPnl.fromJson(Map<String, Object?> json) =>
      ExchangeUnrealizedPnl(
        positionId: json['positionId']?.toString() ?? '',
        symbol: json['symbol']?.toString() ?? '',
        value: (json['value'] as num?)?.toDouble() ?? 0,
        realizedPnl: (json['realizedPnl'] as num?)?.toDouble(),
        fee: (json['fee'] as num?)?.toDouble(),
        funding: (json['funding'] as num?)?.toDouble(),
        openedAt: DateTime.tryParse(
          json['openedAt']?.toString() ?? '',
        )?.toUtc(),
      );
}

final class PositionPnlProjection {
  const PositionPnlProjection({
    required this.positionId,
    required this.symbol,
    required this.unrealized,
    required this.realizedGross,
    required this.fees,
    required this.funding,
    required this.netRealized,
    required this.fills,
    required this.exitFills,
    required this.exchangeFillIds,
    required this.settlement,
    required this.asOf,
    required this.isVerified,
    this.warning,
  });

  final String positionId;
  final String symbol;
  final TradingPnlMetric unrealized;
  final TradingPnlMetric realizedGross;
  final TradingPnlMetric fees;
  final TradingPnlMetric funding;
  final TradingPnlMetric netRealized;
  final List<ExchangePnlFill> fills;
  final List<ExchangePnlFill> exitFills;
  final Set<String> exchangeFillIds;
  final ExchangePositionSettlement? settlement;
  final DateTime asOf;
  final bool isVerified;
  final String? warning;

  Map<String, Object?> toJson() => {
    'positionId': positionId,
    'symbol': symbol,
    'unrealized': unrealized.toJson(),
    'realizedGross': realizedGross.toJson(),
    'fees': fees.toJson(),
    'funding': funding.toJson(),
    'netRealized': netRealized.toJson(),
    'fills': fills.map((item) => item.toJson()).toList(growable: false),
    'settlement': settlement?.toJson(),
    'asOf': asOf.toUtc().toIso8601String(),
    'isVerified': isVerified,
    'warning': warning,
  };

  factory PositionPnlProjection.fromJson(Map<String, Object?> json) {
    final fills = (json['fills'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => ExchangePnlFill.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
    return PositionPnlProjection(
      positionId: json['positionId']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      unrealized: _metricFrom(json['unrealized']),
      realizedGross: _metricFrom(json['realizedGross']),
      fees: _metricFrom(json['fees']),
      funding: _metricFrom(json['funding']),
      netRealized: _metricFrom(json['netRealized']),
      fills: List.unmodifiable(fills),
      exitFills: List.unmodifiable(fills.where((item) => item.reduceOnly)),
      exchangeFillIds: Set.unmodifiable(fills.map((item) => item.tradeId)),
      settlement: _settlementFrom(json['settlement']),
      asOf:
          DateTime.tryParse(json['asOf']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      isVerified: json['isVerified'] == true,
      warning: json['warning']?.toString(),
    );
  }
}

final class TradingPnlProjection {
  const TradingPnlProjection._({
    required this.currency,
    required this.positions,
    required this.accountUnrealized,
    required this.accountRealizedGross,
    required this.accountFees,
    required this.accountFunding,
    required this.accountNetRealized,
    required this.asOf,
    required this.isVerified,
    required this.fillsAvailable,
    required this.settlementsAvailable,
    this.warning,
    this.sessionId,
    this.sessionStartedAt,
  });

  factory TradingPnlProjection.unavailable({
    required String currency,
    required DateTime asOf,
    required String warning,
    Map<String, ExchangeUnrealizedPnl> unrealizedByPosition = const {},
  }) {
    final unrealized = _sumMetric(
      values: unrealizedByPosition.values.map((item) => item.value),
      currency: currency,
      source: TradingPnlSource.bitunixPendingPosition,
      scope: TradingPnlScope.account,
      asOf: asOf,
    );
    final unavailable = TradingPnlMetric.unavailable(
      currency: currency,
      source: TradingPnlSource.bitunixTradeHistory,
      scope: TradingPnlScope.account,
      asOf: asOf,
      warning: warning,
    );
    return TradingPnlProjection._(
      currency: currency,
      positions: const [],
      accountUnrealized: unrealized,
      accountRealizedGross: unavailable,
      accountFees: unavailable,
      accountFunding: unavailable,
      accountNetRealized: unavailable,
      asOf: asOf.toUtc(),
      isVerified: false,
      fillsAvailable: false,
      settlementsAvailable: false,
      warning: warning,
    );
  }

  factory TradingPnlProjection.reconcile({
    required String currency,
    required DateTime asOf,
    required Map<String, ExchangeUnrealizedPnl> unrealizedByPosition,
    required List<ExchangePnlFill> fills,
    required List<ExchangePositionSettlement> settlements,
    bool fillsAvailable = true,
    bool settlementsAvailable = true,
    bool sourceVerified = true,
    bool stale = false,
    String? warning,
    String? sessionId,
    DateTime? sessionStartedAt,
  }) {
    final normalizedAsOf = asOf.toUtc();
    final fillsById = <String, ExchangePnlFill>{};
    final conflicts = <String>[];
    for (final fill in fills) {
      final id = fill.tradeId.trim();
      if (id.isEmpty) {
        conflicts.add('missing tradeId');
        continue;
      }
      final previous = fillsById[id];
      if (previous == null) {
        fillsById[id] = fill;
      } else if (!previous.sameEconomicEvent(fill)) {
        conflicts.add(id);
      }
    }

    final settlementsByKey = <String, ExchangePositionSettlement>{};
    for (final settlement in settlements) {
      final key = settlement.positionKey;
      final previous = settlementsByKey[key];
      if (previous == null) {
        settlementsByKey[key] = settlement;
      } else if (!previous.sameEconomicEvent(settlement)) {
        conflicts.add('settlement:$key');
      }
    }

    final keys = <String>{
      ...unrealizedByPosition.keys,
      ...fillsById.values.map((item) => item.positionKey),
      ...settlementsByKey.keys,
    };
    final positions = <PositionPnlProjection>[];
    final accountBlockingPositionKeys = <String>{};
    for (final key in keys) {
      final open = unrealizedByPosition[key];
      final positionFills =
          fillsById.values
              .where((item) => item.positionKey == key)
              .toList(growable: false)
            ..sort(
              (left, right) => left.occurredAt.compareTo(right.occurredAt),
            );
      final settlement = settlementsByKey[key];
      final symbol =
          open?.symbol ??
          (positionFills.isNotEmpty
              ? positionFills.first.symbol
              : settlement?.symbol ?? '');
      final positionId =
          open?.positionId ??
          (positionFills.isNotEmpty
              ? positionFills.first.positionId
              : settlement?.positionId ?? key);
      final unassignedAttribution = key.startsWith('unassigned-trade:');
      final attributionCouldAffectOpenPosition =
          unassignedAttribution &&
          positionFills.any((fill) {
            final matchingOpen = unrealizedByPosition.values.where(
              (candidate) =>
                  candidate.symbol.trim().toUpperCase() ==
                  fill.symbol.trim().toUpperCase(),
            );
            return matchingOpen.any((candidate) {
              final openedAt = candidate.openedAt;
              return openedAt == null ||
                  !fill.occurredAt.toUtc().isBefore(openedAt.toUtc());
            });
          });
      final identityConflict = conflicts.any(
        (item) =>
            positionFills.any((fill) => fill.tradeId == item) ||
            item == 'settlement:$key' ||
            item == 'missing tradeId',
      );
      final positionConflict = unassignedAttribution || identityConflict;
      final closedEvidenceCanStandAlone =
          settlement != null && positionFills.isNotEmpty && !positionConflict;
      final verified =
          !positionConflict && (sourceVerified || closedEvidenceCanStandAlone);

      final realizedValue = fillsAvailable
          ? positionFills.fold<double>(0, (sum, item) => sum + item.realizedPnl)
          : settlement?.realizedPnl ?? open?.realizedPnl;
      final feeValue = fillsAvailable
          ? positionFills.fold<double>(0, (sum, item) => sum + item.fee)
          : settlement?.fee ?? open?.fee;
      final fundingValue =
          open?.funding ?? (settlementsAvailable ? settlement?.funding : null);
      final tolerance = 0.000001;
      final realizedMismatch =
          fillsAvailable &&
          settlement?.realizedPnl != null &&
          (realizedValue! - settlement!.realizedPnl!).abs() > tolerance;
      final feeMismatch =
          fillsAvailable &&
          settlement?.fee != null &&
          (feeValue! - settlement!.fee!).abs() > tolerance;
      final pendingRealizedMismatch =
          fillsAvailable &&
          open?.realizedPnl != null &&
          (realizedValue! - open!.realizedPnl!).abs() > tolerance;
      final pendingFeeMismatch =
          fillsAvailable &&
          open?.fee != null &&
          (feeValue! - open!.fee!).abs() > tolerance;
      final totalsMismatch =
          realizedMismatch ||
          feeMismatch ||
          pendingRealizedMismatch ||
          pendingFeeMismatch;
      final positionVerified = verified && !totalsMismatch;
      if (identityConflict ||
          attributionCouldAffectOpenPosition ||
          totalsMismatch) {
        accountBlockingPositionKeys.add(key);
      }
      final positionWarning = unassignedAttribution
          ? 'A valid exchange trade remains quarantined because it could not be assigned to one position.'
          : totalsMismatch
          ? 'Trade-history totals diverge from the Bitunix position totals.'
          : positionConflict
          ? 'Conflicting exchange event identity for $key.'
          : warning;

      final realized = _metric(
        value: realizedValue,
        available: fillsAvailable || realizedValue != null,
        verified: positionVerified,
        stale: stale,
        currency: currency,
        source: fillsAvailable
            ? TradingPnlSource.bitunixTradeHistory
            : TradingPnlSource.bitunixPositionHistory,
        scope: TradingPnlScope.position,
        asOf: normalizedAsOf,
        warning: positionWarning,
      );
      final fees = _metric(
        value: feeValue,
        available: fillsAvailable || feeValue != null,
        verified: positionVerified,
        stale: stale,
        currency: currency,
        source: fillsAvailable
            ? TradingPnlSource.bitunixTradeHistory
            : TradingPnlSource.bitunixPositionHistory,
        scope: TradingPnlScope.position,
        asOf: normalizedAsOf,
        warning: positionWarning,
      );
      final funding = _metric(
        value: fundingValue,
        available: fundingValue != null,
        verified: positionVerified,
        stale: stale,
        currency: currency,
        source: open?.funding != null
            ? TradingPnlSource.bitunixPendingPosition
            : TradingPnlSource.bitunixPositionHistory,
        scope: TradingPnlScope.position,
        asOf: normalizedAsOf,
        warning: positionWarning,
      );
      final unrealized = _metric(
        value: open?.value,
        available: open != null,
        verified: positionVerified,
        stale: stale,
        currency: currency,
        source: TradingPnlSource.bitunixPendingPosition,
        scope: TradingPnlScope.position,
        asOf: normalizedAsOf,
        warning: positionWarning,
      );
      final net =
          realized.isAvailable && fees.isAvailable && funding.isAvailable
          ? _metric(
              value: realized.value! - fees.value! + funding.value!,
              available: true,
              verified: positionVerified,
              stale: stale,
              currency: currency,
              source: TradingPnlSource.bitunixTradeHistory,
              scope: TradingPnlScope.position,
              asOf: normalizedAsOf,
              warning: positionWarning,
            )
          : TradingPnlMetric.unavailable(
              currency: currency,
              source: TradingPnlSource.bitunixTradeHistory,
              scope: TradingPnlScope.position,
              asOf: normalizedAsOf,
              warning: warning ?? 'Fee or funding history is incomplete.',
            );

      positions.add(
        PositionPnlProjection(
          positionId: positionId,
          symbol: symbol,
          unrealized: unrealized,
          realizedGross: realized,
          fees: fees,
          funding: funding,
          netRealized: net,
          fills: List.unmodifiable(positionFills),
          exitFills: List.unmodifiable(
            positionFills.where((item) => item.reduceOnly),
          ),
          exchangeFillIds: Set.unmodifiable(
            positionFills.map((item) => item.tradeId),
          ),
          settlement: settlement,
          asOf: normalizedAsOf,
          isVerified: positionVerified,
          warning: positionWarning,
        ),
      );
    }
    positions.sort((left, right) => left.symbol.compareTo(right.symbol));

    final componentsVerified =
        conflicts.isEmpty &&
        sourceVerified &&
        accountBlockingPositionKeys.isEmpty;
    final projectionVerified =
        componentsVerified && fillsAvailable && settlementsAvailable;
    final projectionWarning = conflicts.isEmpty
        ? warning
        : 'Conflicting exchange event IDs: ${conflicts.toSet().join(', ')}';
    final accountUnrealized = _metric(
      value: unrealizedByPosition.values.fold<double>(
        0,
        (sum, item) => sum + item.value,
      ),
      available: true,
      verified: componentsVerified,
      stale: stale,
      currency: currency,
      source: TradingPnlSource.bitunixPendingPosition,
      scope: TradingPnlScope.account,
      asOf: normalizedAsOf,
      warning: projectionWarning,
    );
    final accountRealized = _aggregateMetric(
      positions.map((item) => item.realizedGross),
      currency: currency,
      source: TradingPnlSource.bitunixTradeHistory,
      scope: TradingPnlScope.account,
      asOf: normalizedAsOf,
      verified: componentsVerified && fillsAvailable,
      stale: stale,
      warning: projectionWarning,
    );
    final accountFees = _aggregateMetric(
      positions.map((item) => item.fees),
      currency: currency,
      source: TradingPnlSource.bitunixTradeHistory,
      scope: TradingPnlScope.account,
      asOf: normalizedAsOf,
      verified: componentsVerified && fillsAvailable,
      stale: stale,
      warning: projectionWarning,
    );
    final accountFunding = _aggregateMetric(
      positions.map((item) => item.funding),
      currency: currency,
      source: TradingPnlSource.bitunixPositionHistory,
      scope: TradingPnlScope.account,
      asOf: normalizedAsOf,
      verified: componentsVerified && settlementsAvailable,
      stale: stale,
      warning: projectionWarning,
    );
    final accountNet = _aggregateMetric(
      positions.map((item) => item.netRealized),
      currency: currency,
      source: TradingPnlSource.bitunixTradeHistory,
      scope: TradingPnlScope.account,
      asOf: normalizedAsOf,
      verified: projectionVerified,
      stale: stale,
      warning: projectionWarning,
    );

    return TradingPnlProjection._(
      currency: currency,
      positions: List.unmodifiable(positions),
      accountUnrealized: accountUnrealized,
      accountRealizedGross: accountRealized,
      accountFees: accountFees,
      accountFunding: accountFunding,
      accountNetRealized: accountNet,
      asOf: normalizedAsOf,
      isVerified: projectionVerified,
      fillsAvailable: fillsAvailable,
      settlementsAvailable: settlementsAvailable,
      warning: projectionWarning,
      sessionId: sessionId,
      sessionStartedAt: sessionStartedAt?.toUtc(),
    );
  }

  final String currency;
  final List<PositionPnlProjection> positions;
  final TradingPnlMetric accountUnrealized;
  final TradingPnlMetric accountRealizedGross;
  final TradingPnlMetric accountFees;
  final TradingPnlMetric accountFunding;
  final TradingPnlMetric accountNetRealized;
  final DateTime asOf;
  final bool isVerified;
  final bool fillsAvailable;
  final bool settlementsAvailable;
  final String? warning;
  final String? sessionId;
  final DateTime? sessionStartedAt;

  bool get isReadyForRiskGates =>
      isVerified &&
      fillsAvailable &&
      accountRealizedGross.isAvailable &&
      accountFees.isAvailable;

  TradingPnlProjection asStale({String? warning}) {
    TradingPnlMetric staleMetric(TradingPnlMetric metric) => metric.isAvailable
        ? metric.withState(
            TradingPnlState.stale,
            warning: warning ?? metric.warning,
          )
        : metric;
    final stalePositions = positions
        .map(
          (position) => PositionPnlProjection(
            positionId: position.positionId,
            symbol: position.symbol,
            unrealized: staleMetric(position.unrealized),
            realizedGross: staleMetric(position.realizedGross),
            fees: staleMetric(position.fees),
            funding: staleMetric(position.funding),
            netRealized: staleMetric(position.netRealized),
            fills: position.fills,
            exitFills: position.exitFills,
            exchangeFillIds: position.exchangeFillIds,
            settlement: position.settlement,
            asOf: position.asOf,
            isVerified: position.isVerified,
            warning: warning ?? position.warning,
          ),
        )
        .toList(growable: false);
    return TradingPnlProjection._(
      currency: currency,
      positions: List.unmodifiable(stalePositions),
      accountUnrealized: staleMetric(accountUnrealized),
      accountRealizedGross: staleMetric(accountRealizedGross),
      accountFees: staleMetric(accountFees),
      accountFunding: staleMetric(accountFunding),
      accountNetRealized: staleMetric(accountNetRealized),
      asOf: asOf,
      isVerified: isVerified,
      fillsAvailable: fillsAvailable,
      settlementsAvailable: settlementsAvailable,
      warning: warning ?? this.warning,
      sessionId: sessionId,
      sessionStartedAt: sessionStartedAt,
    );
  }

  TradingPnlProjection forSession({
    required String sessionId,
    required DateTime startedAt,
    Set<String>? ownedPositionIds,
  }) {
    final start = startedAt.toUtc();
    final includedPositions = ownedPositionIds == null
        ? positions
        : positions
              .where(
                (position) => ownedPositionIds.contains(position.positionId),
              )
              .toList(growable: false);
    final fills = includedPositions
        .expand((position) => position.fills)
        .where((fill) => !fill.occurredAt.toUtc().isBefore(start))
        .toList(growable: false);
    final settlements = includedPositions
        .map((position) => position.settlement)
        .whereType<ExchangePositionSettlement>()
        .where((settlement) => !settlement.closedAt.toUtc().isBefore(start))
        .toList(growable: false);
    final unrealized = <String, ExchangeUnrealizedPnl>{
      for (final position in includedPositions)
        if (position.unrealized.isAvailable)
          position.positionId: ExchangeUnrealizedPnl(
            positionId: position.positionId,
            symbol: position.symbol,
            value: position.unrealized.value!,
            funding: position.funding.value,
          ),
    };
    return TradingPnlProjection.reconcile(
      currency: currency,
      asOf: asOf,
      unrealizedByPosition: unrealized,
      fills: fills,
      settlements: settlements,
      fillsAvailable: fillsAvailable,
      settlementsAvailable: settlementsAvailable,
      sourceVerified: includedPositions.every(
        (position) => position.isVerified,
      ),
      stale: includedPositions.any(
        (item) => item.unrealized.state == TradingPnlState.stale,
      ),
      warning: warning,
      sessionId: sessionId,
      sessionStartedAt: start,
    );
  }

  PositionPnlProjection? forPositionId(String positionId) {
    final normalized = positionId.trim();
    for (final position in positions) {
      if (position.positionId.trim() == normalized) return position;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'currency': currency,
    'positions': positions.map((item) => item.toJson()).toList(growable: false),
    'accountUnrealized': accountUnrealized.toJson(),
    'accountRealizedGross': accountRealizedGross.toJson(),
    'accountFees': accountFees.toJson(),
    'accountFunding': accountFunding.toJson(),
    'accountNetRealized': accountNetRealized.toJson(),
    'asOf': asOf.toUtc().toIso8601String(),
    'isVerified': isVerified,
    'fillsAvailable': fillsAvailable,
    'settlementsAvailable': settlementsAvailable,
    'warning': warning,
    'sessionId': sessionId,
    'sessionStartedAt': sessionStartedAt?.toUtc().toIso8601String(),
  };

  factory TradingPnlProjection.fromJson(Map<String, Object?> json) =>
      TradingPnlProjection._(
        currency: json['currency']?.toString() ?? 'USDT',
        positions: List.unmodifiable(
          (json['positions'] as List<Object?>? ?? const [])
              .whereType<Map<Object?, Object?>>()
              .map(
                (item) => PositionPnlProjection.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              ),
        ),
        accountUnrealized: _metricFrom(json['accountUnrealized']),
        accountRealizedGross: _metricFrom(json['accountRealizedGross']),
        accountFees: _metricFrom(json['accountFees']),
        accountFunding: _metricFrom(json['accountFunding']),
        accountNetRealized: _metricFrom(json['accountNetRealized']),
        asOf:
            DateTime.tryParse(json['asOf']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isVerified: json['isVerified'] == true,
        fillsAvailable: json['fillsAvailable'] == true,
        settlementsAvailable: json['settlementsAvailable'] == true,
        warning: json['warning']?.toString(),
        sessionId: json['sessionId']?.toString(),
        sessionStartedAt: DateTime.tryParse(
          json['sessionStartedAt']?.toString() ?? '',
        )?.toUtc(),
      );
}

TradingPnlMetric _metric({
  required double? value,
  required bool available,
  required bool verified,
  required bool stale,
  required String currency,
  required TradingPnlSource source,
  required TradingPnlScope scope,
  required DateTime asOf,
  required String? warning,
}) {
  if (!available || value == null) {
    return TradingPnlMetric.unavailable(
      currency: currency,
      source: source,
      scope: scope,
      asOf: asOf,
      warning: warning,
    );
  }
  final base = TradingPnlMetric.confirmed(
    value: value,
    currency: currency,
    source: source,
    scope: scope,
    asOf: asOf,
  );
  if (!verified) {
    return base.withState(TradingPnlState.unverified, warning: warning);
  }
  if (stale) {
    return base.withState(TradingPnlState.stale, warning: warning);
  }
  return base;
}

TradingPnlMetric _aggregateMetric(
  Iterable<TradingPnlMetric> metrics, {
  required String currency,
  required TradingPnlSource source,
  required TradingPnlScope scope,
  required DateTime asOf,
  required bool verified,
  required bool stale,
  required String? warning,
}) {
  final values = metrics.toList(growable: false);
  final hasUnavailableComponent = verified
      ? values.any((item) => item.value == null)
      : values.any((item) => !item.isAvailable);
  if (hasUnavailableComponent) {
    return TradingPnlMetric.unavailable(
      currency: currency,
      source: source,
      scope: scope,
      asOf: asOf,
      warning: warning ?? 'One or more PnL components are unavailable.',
    );
  }
  return _metric(
    value: values.fold<double>(0, (sum, item) => sum + item.value!),
    available: true,
    verified: verified,
    stale: stale,
    currency: currency,
    source: source,
    scope: scope,
    asOf: asOf,
    warning: warning,
  );
}

TradingPnlMetric _sumMetric({
  required Iterable<double> values,
  required String currency,
  required TradingPnlSource source,
  required TradingPnlScope scope,
  required DateTime asOf,
}) => TradingPnlMetric.confirmed(
  value: values.fold<double>(0, (sum, item) => sum + item),
  currency: currency,
  source: source,
  scope: scope,
  asOf: asOf,
);

ExchangePositionSettlement? _settlementFrom(Object? raw) {
  if (raw is Map<String, Object?>) {
    return ExchangePositionSettlement.fromJson(raw);
  }
  if (raw is Map<Object?, Object?>) {
    return ExchangePositionSettlement.fromJson(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
  return null;
}

TradingPnlMetric _metricFrom(Object? raw) {
  if (raw is Map<String, Object?>) return TradingPnlMetric.fromJson(raw);
  if (raw is Map<Object?, Object?>) {
    return TradingPnlMetric.fromJson(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
  return TradingPnlMetric.unavailable(
    currency: 'USDT',
    source: TradingPnlSource.bitunixTradeHistory,
    scope: TradingPnlScope.account,
    asOf: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}
