part of 'owner_alpha_page.dart';

class _StrategyCard extends StatelessWidget {
  const _StrategyCard();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schema_outlined, color: QuantaraColors.violet),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.strategies,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _InfoButton(
                title: strings.strategies,
                paragraphs: [
                  strings.strategyDescription,
                  strings.strategyRules,
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          StatusPill(
            label: strings.strategyVersion,
            color: QuantaraColors.violet,
            icon: Icons.verified_outlined,
          ),
          const SizedBox(height: 12),
          Text(strings.strategyDescription),
          const SizedBox(height: 8),
          Text(
            strings.strategyRules,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return IconButton(
      tooltip: strings.info,
      icon: const Icon(Icons.info_outline_rounded, size: 20),
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final paragraph in paragraphs) ...[
                    Text(paragraph),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
