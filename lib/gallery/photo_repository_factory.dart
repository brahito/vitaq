import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'android/media_store_photo_repository.dart';
import 'cached_photo_repository.dart';
import 'photo_repository.dart';

PhotoRepository createPhotoRepository() {
  if (!kIsWeb && Platform.isAndroid) {
    return CachedPhotoRepository(MediaStorePhotoRepository());
  }
  return const UnsupportedPhotoRepository();
}
