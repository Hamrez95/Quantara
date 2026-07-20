part of 'stable_cockpit_page.dart';

class _MarketsView extends StatefulWidget {
  const _MarketsView({required this.quotes});

  final List<MarketQuote> quotes;

  @override
  State<_MarketsView> createState() => _MarketsViewState();
}

class _MarketsViewState extends State<_MarketsView> {
  int _selectedIndex = 0;
  String _timeframe = '1h';

  @override
  void didUpdateWidget(covariant _MarketsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.quotes.length) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.quotes.isEmpty) {
      return const SectionCard(
        child: Text('بازاری برای نمایش وجود ندارد.'),
      );
    }

    final selected = widget.quotes[_selectedIndex];
    final positive = selected.changePercent >= 0;
    final chartColor = positive ? QuantaraColors.success : QuantaraColors.danger;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected.symbol,
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          QuantaraNumberFormat.marketValue(
                            selected.price,
                            unit: 'USDT',
                          ),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: StatusPill(
                      label: QuantaraNumberFormat.marketPercent(
                        selected.changePercent,
                      ),
                      color: chartColor,
                      icon: positive
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['15m', '1h', '4h', '1D']
                    .map(
                      (value) => ChoiceChip(
                        label: Text(value, textDirection: TextDirection.ltr),
                        selected: _timeframe == value,
                        onSelected: (_) => setState(() => _timeframe = value),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 180,
                child: SparklineChart(
                  values: selected.sparkline,
                  color: chartColor,
                  height: 180,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_graph_rounded, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'نماد و بازه زمانی پویا هستند. پس از اتصال کندل‌ها، همین بخش با موتور TradingView به‌روزرسانی زنده می‌شود.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (var index = 0; index < widget.quotes.length; index++) ...[
                _QuoteRow(
                  quote: widget.quotes[index],
                  selected: index == _selectedIndex,
                  onTap: () => setState(() => _selectedIndex = index),
                ),
                if (index != widget.quotes.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
