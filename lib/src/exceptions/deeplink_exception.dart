class DeeplinkException implements Exception {
  final String message;
  final String? code;

  DeeplinkException(this.message, {this.code});

  @override
  String toString() => 'DeeplinkException: $message${code != null ? ' (code: $code)' : ''}';
}
