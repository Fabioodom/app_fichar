export 'cross_platform_storage_stub.dart'
  if (dart.library.io) 'cross_platform_storage_mobile.dart'
  if (dart.library.html) 'cross_platform_storage_web.dart';