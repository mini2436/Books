class AppConfig {
  AppConfig._();

  static const String _defaultServerAddress = '192.168.110.159';
  static const int defaultPort = 8080;

  static String get defaultServerAddress {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) {
      return normalizeAddress(override);
    }
    return _defaultServerAddress;
  }

  static String get defaultApiBaseUrl => normalizeBaseUrl(defaultServerAddress);

  static String normalizeAddress(String input) {
    final uri = Uri.parse(normalizeBaseUrl(input));
    final portSuffix = uri.hasPort && uri.port != defaultPort
        ? ':${uri.port}'
        : '';
    final normalizedPath = uri.path == '/' ? '' : uri.path;
    return '${uri.host}$portSuffix$normalizedPath';
  }

  static String normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    final candidate = trimmed.isEmpty ? _defaultServerAddress : trimmed;
    final withScheme = candidate.contains('://')
        ? candidate
        : 'http://$candidate';
    final parsed = Uri.parse(withScheme);
    final host = parsed.host.isEmpty ? _defaultServerAddress : parsed.host;
    final scheme = parsed.scheme.isEmpty ? 'http' : parsed.scheme;
    final pathSegments = parsed.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();

    final normalized = Uri(
      scheme: scheme,
      host: host,
      port: parsed.hasPort ? parsed.port : defaultPort,
      pathSegments: pathSegments.isEmpty ? null : pathSegments,
    );

    return normalized.toString();
  }
}
