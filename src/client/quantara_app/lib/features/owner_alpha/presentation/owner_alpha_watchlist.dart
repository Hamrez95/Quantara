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
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(QuantaraSpacing.md),
            child: SectionHeading(
              title: strings.myWatchlist,
              subtitle: strings.futuresLimit,
              trailing: FilledButton.tonalIcon(
                onPressed: controller.isLoading ? null : onAddSymbol,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(strings.add),
              ),
            ),
          ),
          const Divider(),
          for (var index = 0; index < snapshot.radar.length; index++) ...[
            _WatchlistRow(
              result: snapshot.radar[index],
              canRemove: snapshot.radar.length > 1,
              onOpen: () => onOpenAnalysis(snapshot.radar[index].quote.symbol),
              onRemove: () =>
                  controller.removeSymbol(snapshot.radar[index].quote.symbol),
            ),
            if (index != snapshot.radar.length - 1)
              const Divider(indent: 64),
          ],
        ],
      ),
    );
  }
}

class _WatchlistRow extends StatelessWidget {
  const _WatchlistRow({
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
    final direction = _ideaLabel(context, result.idea.direction);
    return MarketListRow(
      symbol: quote.symbol,
      name: '${quote.displayName} · $direction',
      price: QuantaraNumberFormat.marketValue(quote.lastPrice),
      change: QuantaraNumberFormat.marketPercent(quote.changePercent),
      changeColor: changeColor,
      onTap: onOpen,
      trailing: canRemove
          ? PopupMenuButton<_WatchlistAction>(
              tooltip: strings.removeSymbol(quote.symbol),
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (action) {
                if (action == _WatchlistAction.remove) {
                  onRemove();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _WatchlistAction.remove,
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: QuantaraSpacing.xs),
                      Text(strings.removeSymbol(quote.symbol)),
                    ],
                  ),
                ),
              ],
            )
          : const Icon(Icons.candlestick_chart_outlined, size: 20),
    );
  }
}

enum _WatchlistAction { remove }
