import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final annotationChangeNotifierProvider = Provider<AnnotationChangeNotifier>(
  (ref) => AnnotationChangeNotifier(),
);

class AnnotationChangeNotifier extends ChangeNotifier {
  int _version = 0;

  int get version => _version;

  void markChanged() {
    _version += 1;
    notifyListeners();
  }
}
