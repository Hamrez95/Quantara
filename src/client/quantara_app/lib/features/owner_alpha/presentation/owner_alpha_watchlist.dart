part of 'owner_alpha_page.dart';

class _WatchlistView extends StatelessWidget {
  const _WatchlistView({
    required this.controller,
    required this.snapshot,
    required this.onOpenAnalysis,
    required this.onAddSymbol,
  });

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;
  final ValueChanged<String> onOpenAnalysis;
  final VoidCallback onAddSymbol;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.myWatchlist,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              strings.futuresLimit,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: controller.isLoading ? null : onAddSymbol,
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.add),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < snapshot.radar.length; index++) ...[
          _WatchlistTile(
            result: snapshot.radar[index],
            canRemove: snapshot.radar.length > 1,
            onOpen: () => onOpenAnalysis(snapshot.radar[index].quote.symbol),
            onRemove: () =>
                controller.removeSymbol(snapshot.radar[index].quote.symbol),
          ),
          if (index != snapshot.radar.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _WatchlistTile extends StatelessWidget {
  const _WatchlistTile({
    required this.result,
    required this.canRemove,
    required this.onOpen,
    required this.onRemove,
  });

  final SymbolRadarResult result;
  final bool canRemove;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final quote = result.quote;
    final changeColor = quote.changePercent >= 0
        ? QuantaraColors.success
        : QuantaraColors.danger;
    final largeText = MediaQuery.of(context).textScaler.scale(1) > 1.4;
    final identity = Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: SizedBox.square(
            dimension: 46,
            child: Center(
              child: Text(
                quote.symbol.substring(0, 1),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                quote.symbol,
                textDirection: TextDirection.ltr,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(quote.displayName),
            ],
          ),
        ),
      ],
    );
    final price = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          QuantaraNumberFormat.marketValue(quote.lastPrice),
          textDirection: TextDirection.ltr,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          QuantaraNumberFormat.marketPercent(quote.changePercent),
          textDirection: TextDirection.ltr,
          style: TextStyle(color: changeColor, fontWeight: FontWeight.w800),
        ),
      ],
    );
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (largeText) ...[
            identity,
            const SizedBox(height: 10),
            Align(alignment: AlignmentDirectional.centerEnd, child: price),
          ] else
            Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 12),
                price,
              ],
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label: _ideaLabel(context, result.idea.direction),
                color: _ideaColor(context, result.idea.direction),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  tooltip: strings.removeSymbol(quote.symbol),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(strings.analysis),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
