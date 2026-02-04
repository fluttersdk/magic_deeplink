import 'package:fluttersdk_magic/fluttersdk_magic.dart';
import 'package:fluttersdk_magic_deeplink/src/handlers/deeplink_handler.dart';

class RouteDeeplinkHandler extends DeeplinkHandler {
  final List<String> paths;
  final List<RegExp> _patterns;

  RouteDeeplinkHandler({required this.paths})
      : _patterns = paths.map(_compilePattern).toList();

  static RegExp _compilePattern(String pattern) {
    // Escape special regex characters except *
    var regex = pattern.replaceAllMapped(
      RegExp(r'[.+^${}()|[\]\\]'),
      (match) => '\\${match.group(0)}',
    );

    // Replace * with .* (match anything)
    regex = regex.replaceAll('*', '.*');

    // Replace :param with [^/]+ (match segment)
    regex = regex.replaceAll(RegExp(r':\w+'), '[^/]+');

    // Ensure full match
    return RegExp('^$regex\$', caseSensitive: false);
  }

  @override
  bool canHandle(Uri uri) {
    String path = uri.path;

    // Normalize path: remove trailing slash unless it's just "/"
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    return _patterns.any((p) => p.hasMatch(path));
  }

  @override
  Future<bool> handle(Uri uri) async {
    MagicRoute.to(uri.path, query: uri.queryParameters);
    return true;
  }
}
