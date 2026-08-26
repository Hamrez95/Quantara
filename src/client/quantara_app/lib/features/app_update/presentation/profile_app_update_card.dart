import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../application/app_update_controller.dart';
import '../data/app_update_channel_store.dart';
import '../data/app_update_manifest_client.dart';
import '../domain/app_update_models.dart';

final class AppUpdateProfileConfiguration {
  const AppUpdateProfileConfiguration({
    required this.stableManifestUrl,
    required this.canaryManifestUrl,
    this.internalManifestUrl = '',
  });

  const AppUpdateProfileConfiguration.fromEnvironment()
    : stableManifestUrl = const String.fromEnvironment(
        'QUANTARA_UPDATE_STABLE_MANIFEST_URL',
      ),
      canaryManifestUrl = const String.fromEnvironment(
        'QUANTARA_UPDATE_CANARY_MANIFEST_URL',
      ),
      internalManifestUrl = const String.fromEnvironment(
        'QUANTARA_UPDATE_INTERNAL_MANIFEST_URL',
      );

  final String stableManifestUrl;
  final String canaryManifestUrl;
  final String internalManifestUrl;

  Uri? get stableManifestUri => _validatedHttpsUri(stableManifestUrl);
  Uri? get canaryManifestUri => _validatedHttpsUri(canaryManifestUrl);
  Uri? get internalManifestUri => _validatedHttpsUri(internalManifestUrl);

  bool get isConfigured =>
      stableManifestUri != null && canaryManifestUri != null;
  bool get internalEnabled => internalManifestUri != null;

  static Uri? _validatedHttpsUri(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }
}

class ProfileAppUpdateCard extends StatefulWidget {
  const ProfileAppUpdateCard({
    this.configuration = const AppUpdateProfileConfiguration.fromEnvironment(),
    super.key,
  });

  final AppUpdateProfileConfiguration configuration;

  @override
  State<ProfileAppUpdateCard> createState() => _ProfileAppUpdateCardState();
}

class _ProfileAppUpdateCardState extends State<ProfileAppUpdateCard> {
  http.Client? _client;
  AppUpdateController? _controller;
  String? _initializationError;
  bool _initializing = true;
  bool _initializationStarted = false;

  bool get _persian => Localizations.localeOf(context).languageCode == 'fa';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializationStarted) return;
    _initializationStarted = true;
    unawaited(_initialize(Localizations.localeOf(context).languageCode));
  }

  Future<void> _initialize(String languageCode) async {
    final configuration = widget.configuration;
    if (!configuration.isConfigured) {
      if (mounted) {
        setState(() {
          _initializationError =
              'Update manifest endpoints are not configured for this build.';
          _initializing = false;
        });
      }
      return;
    }

    final platform = _releasePlatform();
    if (platform == null) {
      if (mounted) {
        setState(() {
          _initializationError =
              'In-app update checks are unavailable on this platform.';
          _initializing = false;
        });
      }
      return;
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final buildNumber = int.tryParse(package.buildNumber.trim());
      if (package.version.trim().isEmpty ||
          buildNumber == null ||
          buildNumber < 1) {
        throw const FormatException('Installed app version metadata is invalid.');
      }
      final client = http.Client();
      final controller = AppUpdateController(
        manifestClient: AppUpdateManifestClient(
          client: client,
          stableManifestUri: configuration.stableManifestUri!,
          canaryManifestUri: configuration.canaryManifestUri!,
          internalManifestUri: configuration.internalManifestUri,
        ),
        currentVersion: package.version.trim(),
        currentBuildNumber: buildNumber,
        platform: platform,
        initialChannel: AppReleaseChannel.stable,
        languageCode: languageCode,
        channelStore: const PlatformAppUpdateChannelStore(),
      );
      await controller.restoreChannel();
      if (!mounted) {
        controller.dispose();
        client.close();
        return;
      }
      setState(() {
        _client = client;
        _controller = controller;
        _initializing = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _initializationError =
              'Installed version could not be read safely (${error.runtimeType}).';
          _initializing = false;
        });
      }
    }
  }

  AppReleasePlatform? _releasePlatform() {
    if (kIsWeb) return AppReleasePlatform.pwa;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AppReleasePlatform.android,
      TargetPlatform.windows => AppReleasePlatform.windows,
      _ => null,
    };
  }

  @override
  void dispose() {
    _controller?.dispose();
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      accentColor: QuantaraColors.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.system_update_alt_rounded,
                color: QuantaraColors.cyan,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _persian ? 'به‌روزرسانی برنامه' : 'App update',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _persian
                          ? 'نسخه نصب‌شده و کانال انتشار را بررسی کن. نصب فقط پس از اعتبارسنجی artifact فعال می‌شود.'
                          : 'Check the installed version and release channel. Installation stays disabled until the artifact can be verified safely.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_initializing)
            const LinearProgressIndicator()
          else if (_controller == null)
            _UnavailableUpdateState(
              message: _initializationError ?? 'Update checks are unavailable.',
              persian: _persian,
            )
          else
            AnimatedBuilder(
              animation: _controller!,
              builder: (context, _) => _UpdateControllerView(
                controller: _controller!,
                internalEnabled: widget.configuration.internalEnabled,
                persian: _persian,
              ),
            ),
        ],
      ),
    );
  }
}

class _UnavailableUpdateState extends StatelessWidget {
  const _UnavailableUpdateState({required this.message, required this.persian});

  final String message;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: QuantaraColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: QuantaraColors.warning.withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: QuantaraColors.warning,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                persian
                    ? 'سرویس به‌روزرسانی برای این بیلد فعال نشده است. هیچ فایل یا آدرس جایگزینی حدس زده نمی‌شود.'
                    : '$message No fallback artifact or endpoint will be guessed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateControllerView extends StatelessWidget {
  const _UpdateControllerView({
    required this.controller,
    required this.internalEnabled,
    required this.persian,
  });

  final AppUpdateController controller;
  final bool internalEnabled;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    final channels = <AppReleaseChannel>[
      AppReleaseChannel.stable,
      AppReleaseChannel.canary,
      if (internalEnabled) AppReleaseChannel.internal,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          persian
              ? 'نسخه فعلی: ${controller.currentVersion} (${controller.currentBuildNumber})'
              : 'Current: ${controller.currentVersion} (${controller.currentBuildNumber})',
          textDirection: TextDirection.ltr,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<AppReleaseChannel>(
          segments: [
            for (final channel in channels)
              ButtonSegment<AppReleaseChannel>(
                value: channel,
                label: Text(channel.name),
              ),
          ],
          selected: {controller.channel},
          showSelectedIcon: false,
          onSelectionChanged: controller.isBusy
              ? null
              : (selection) => unawaited(
                  controller.setChannel(selection.first),
                ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: controller.isBusy
              ? null
              : () => unawaited(controller.check()),
          icon: controller.isBusy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(persian ? 'بررسی نسخه جدید' : 'Check for update'),
        ),
        if (controller.error != null) ...[
          const SizedBox(height: 10),
          Text(
            persian
                ? 'بررسی نسخه با خطا متوقف شد؛ وضعیت فعلی برنامه تغییر نکرد.'
                : controller.error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (result != null) ...[
          const SizedBox(height: 14),
          _UpdateResultView(result: result, persian: persian),
        ],
      ],
    );
  }
}

class _UpdateResultView extends StatelessWidget {
  const _UpdateResultView({required this.result, required this.persian});

  final AppUpdateCheckResult result;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final artifact = result.artifact;
    final status = result.revoked
        ? (persian ? 'بیلد فعلی لغو شده' : 'Current build revoked')
        : result.updateAvailable
        ? (persian ? 'نسخه جدید موجود است' : 'Update available')
        : (persian ? 'نسخه فعلی به‌روز است' : 'Up to date');
    final color = result.revoked || result.mandatory
        ? QuantaraColors.warning
        : result.updateAvailable
        ? QuantaraColors.cyan
        : QuantaraColors.success;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (artifact != null) ...[
              const SizedBox(height: 5),
              Text(
                persian
                    ? 'آخرین نسخه: ${artifact.version} (${artifact.buildNumber})'
                    : 'Latest: ${artifact.version} (${artifact.buildNumber})',
                textDirection: TextDirection.ltr,
              ),
            ],
            if (result.releaseNotes.trim().isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(result.releaseNotes.trim()),
            ],
            if (result.updateAvailable) ...[
              const SizedBox(height: 10),
              Text(
                persian
                    ? 'دانلود/نصب هنوز غیرفعال است تا checksum و هویت بسته روی همین پلتفرم قبل از hand-off تأیید شود.'
                    : 'Download/install remains disabled until checksum and package identity can be verified on this platform before hand-off.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
