class ApiConfiguration {
  const ApiConfiguration._(this.baseUri);

  final Uri baseUri;

  static const String configuredUrl = String.fromEnvironment(
    'STOREOS_API_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  factory ApiConfiguration.fromEnvironment() =>
      ApiConfiguration.parse(configuredUrl);

  factory ApiConfiguration.parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Ungültige StoreOS-Serveradresse.');
    }

    final host = uri.host.toLowerCase();
    final isLoopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
      throw const FormatException(
        'Für externe Server ist eine HTTPS-Adresse erforderlich.',
      );
    }

    return ApiConfiguration._(
      uri.replace(path: '/', query: null, fragment: null),
    );
  }
}
