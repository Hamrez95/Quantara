import 'package:flutter/material.dart';

import '../application/app_update_controller.dart';
import '../domain/app_update_models.dart';

/// Profile-facing, fail-closed update surface.
///
/// Network checks stay inside [AppUpdateController]. Artifact download/install
/// is deliberately delegated to an explicit owner action so this widget never
/// gains silent installer authority.
final class AppUpdateCard extends StatelessWidget {
  const AppUpdateCard({
    required this.controller,
    required this.locale,
    this.onDownloadVerifiedArtifact,
    super.key,
  });

  final AppUpdateController? controller;
  final Locale locale;
  final Future<void> Function(AppReleaseArtifact artifact)?
  onDownloadVerifiedArtifact;

  bool get _persian => locale.languageCode == 'fa';

  Future<void> _confirmDownload(
    BuildContext context,
    AppReleaseArtifact artifact,
  ) async {
    final callback = onDownloadVerifiedArtifact;
    if (callback == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('app-update-confirm-dialog'),
        title: Text(_persian ? 'دریافت به‌روزرسانی؟' : 'Download update?'),
        content: Text(
          _persian
              ? 'Quantara فایل نصب را دانلود و صحت آن را بررسی می‌کند. نصب یا راه‌اندازی مجدد فقط با اقدام صریح بعدی شما انجام می‌شود.'
              : 'Quantara will download and verify the installer. Installation or restart still requires your next explicit action.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('app-update-confirm-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_persian ? 'انصراف' : 'Cancel'),
          ),
          FilledButton(
            key: const ValueKey('app-update-confirm-download'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_persian ? 'دانلود و بررسی' : 'Download & verify'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await callback(artifact);
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateController = controller;
    if (updateController == null) {
      return _frame(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            const SizedBox(height: 12),
            Text(
              _persian
                  ? 'بررسی به‌روزرسانی روی این build پیکربندی نشده است.'
                  : 'Update checks are not configured for this build.',
              key: const ValueKey('app-update-unconfigured'),
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: updateController,
      builder: (context, _) {
        final result = updateController.result;
        final artifact = result?.artifact;
        return _frame(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _metric(
                    context,
                    _persian ? 'نسخه فعلی' : 'Current version',
                    '${updateController.currentVersion} '
                    '(${updateController.currentBuildNumber})',
                  ),
                  DropdownButton<AppReleaseChannel>(
                    key: const ValueKey('app-update-channel'),
                    value: updateController.channel,
                    onChanged: updateController.isBusy
                        ? null
                        : (value) {
                            if (value != null) {
                              updateController.setChannel(value);
                            }
                          },
                    items: AppReleaseChannel.values
                        .map(
                          (channel) => DropdownMenuItem(
                            value: channel,
                            child: Text(channel.name),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('app-update-check'),
                    onPressed: updateController.isBusy
                        ? null
                        : updateController.check,
                    icon: updateController.isBusy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(
                      _persian ? 'بررسی نسخه جدید' : 'Check for updates',
                    ),
                  ),
                ],
              ),
              if (updateController.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  updateController.error!,
                  key: const ValueKey('app-update-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (result != null) ...[
                const SizedBox(height: 12),
                _status(context, result),
                if (artifact != null) ...[
                  const SizedBox(height: 10),
                  _artifactMetadata(context, artifact),
                ],
                if (result.releaseNotes.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    result.releaseNotes,
                    key: const ValueKey('app-update-release-notes'),
                  ),
                ],
                if (result.updateAvailable && artifact != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('app-update-download'),
                    onPressed:
                        onDownloadVerifiedArtifact == null ||
                            updateController.isBusy
                        ? null
                        : () => _confirmDownload(context, artifact),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      _persian
                          ? 'دانلود و بررسی فایل نصب'
                          : 'Download & verify installer',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _persian
                        ? 'نصب فقط با اقدام صریح شما ادامه پیدا می‌کند؛ Quantara نصب بی‌صدا انجام نمی‌دهد.'
                        : 'Installation continues only after your explicit action; Quantara never installs silently.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _frame(BuildContext context, {required Widget child}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.system_update_alt_rounded),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _persian ? 'به‌روزرسانی برنامه' : 'App update',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                _persian
                    ? 'کانال انتشار، وضعیت نسخه و یادداشت‌های انتشار'
                    : 'Release channel, version status and release notes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    return Semantics(
      label: '$label: $value',
      child: Chip(label: Text('$label: $value')),
    );
  }

  Widget _artifactMetadata(
    BuildContext context,
    AppReleaseArtifact artifact,
  ) {
    final packageId = artifact.packageId?.trim();
    final signingIdentity = artifact.signingIdentity?.trim();
    final architecture = artifact.architecture?.trim();
    return Container(
      key: const ValueKey('app-update-artifact-metadata'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metadataLine(
            key: const ValueKey('app-update-latest-version'),
            label: _persian ? 'نسخه جدید' : 'Latest version',
            value: '${artifact.version} (${artifact.buildNumber})',
          ),
          if (packageId != null && packageId.isNotEmpty)
            _metadataLine(
              key: const ValueKey('app-update-package-id'),
              label: _persian ? 'شناسه بسته' : 'Package',
              value: packageId,
            ),
          if (signingIdentity != null && signingIdentity.isNotEmpty)
            _metadataLine(
              key: const ValueKey('app-update-signing-suffix'),
              label: _persian ? 'امضاکننده' : 'Signer',
              value: _safeSuffix(signingIdentity),
            ),
          _metadataLine(
            key: const ValueKey('app-update-integrity'),
            label: 'SHA-256',
            value: _safeSuffix(artifact.sha256),
          ),
          if (architecture != null && architecture.isNotEmpty)
            _metadataLine(
              key: const ValueKey('app-update-architecture'),
              label: _persian ? 'معماری' : 'Architecture',
              value: architecture,
            ),
        ],
      ),
    );
  }

  Widget _metadataLine({
    required Key key,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(key: key, '$label: $value'),
    );
  }

  String _safeSuffix(String value) {
    final trimmed = value.trim();
    const visibleCharacters = 12;
    if (trimmed.length <= visibleCharacters) return trimmed;
    return '…${trimmed.substring(trimmed.length - visibleCharacters)}';
  }

  Widget _status(BuildContext context, AppUpdateCheckResult result) {
    final String message;
    if (!result.updateAvailable) {
      message = _persian
          ? 'این build به‌روز است.'
          : 'This build is up to date.';
    } else if (result.revoked) {
      message = _persian
          ? 'این build لغو شده است؛ به‌روزرسانی الزامی است.'
          : 'This build is revoked; updating is mandatory.';
    } else if (result.mandatory) {
      message = _persian
          ? 'به‌روزرسانی الزامی در دسترس است.'
          : 'A mandatory update is available.';
    } else {
      message = _persian
          ? 'نسخه جدید در دسترس است.'
          : 'A new version is available.';
    }
    return Text(
      message,
      key: const ValueKey('app-update-status'),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}
