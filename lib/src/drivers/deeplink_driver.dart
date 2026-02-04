/// Abstract class defining the contract for deep link drivers.
abstract class DeeplinkDriver {
  /// The name of the driver.
  String get name;

  /// Returns true if the driver is supported on the current platform.
  bool get isSupported;

  /// Initializes the driver with the given configuration.
  Future<void> initialize(Map<String, dynamic> config);

  /// Returns the initial link that opened the application, if any.
  Future<Uri?> getInitialLink();

  /// Returns a stream of incoming links.
  Stream<Uri> get onLink;

  /// Disposes resources used by the driver.
  void dispose();
}
