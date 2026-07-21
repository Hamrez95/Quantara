import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/cockpit_models.dart';
import 'api_cockpit_repository.dart';
import 'mock_cockpit_repository.dart';

abstract final class CockpitRepositoryFactory {
  static CockpitRepository create({
    String apiBaseUrl = const String.fromEnvironment('QUANTARA_API_BASE_URL'),
    http.Client? client,
  }) {
    final value = apiBaseUrl.trim();
    if (value.isEmpty) {
      return const MockCockpitRepository();
    }

    final baseUri = Uri.tryParse(value);
    if (baseUri == null ||
        !baseUri.hasScheme ||
        baseUri.host.isEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        baseUri.userInfo.isNotEmpty ||
        (baseUri.path.isNotEmpty && baseUri.path != '/')) {
      throw const CockpitContractException(
        'QUANTARA_API_BASE_URL must be an origin without credentials, query, or path.',
      );
    }

    final localDevelopmentHost =
        baseUri.host == 'localhost' ||
        baseUri.host == '127.0.0.1' ||
        baseUri.host == '::1' ||
        baseUri.host == '10.0.2.2';
    final secure =
        baseUri.scheme == 'https' ||
        (!kReleaseMode && baseUri.scheme == 'http' && localDevelopmentHost);
    if (!secure) {
      throw const CockpitContractException(
        'Release API endpoints must use HTTPS. Plain HTTP is limited to local debug builds.',
      );
    }

    final endpoint = baseUri.replace(
      path: '/api/v1/cockpit',
      query: null,
      fragment: null,
    );
    final primary = ApiCockpitRepository(
      client: client ?? http.Client(),
      endpoint: endpoint,
    );
    return FallbackCockpitRepository(primary, const MockCockpitRepository());
  }
}
