import 'package:flutter/foundation.dart';

class PendingFileHandler {
  static final PendingFileHandler _instance = PendingFileHandler._internal();
  
  factory PendingFileHandler() {
    return _instance;
  }
  
  PendingFileHandler._internal();
  
  final ValueNotifier<String?> pendingFilePath = ValueNotifier<String?>(null);
  
  void setPendingFile(String path) {
    pendingFilePath.value = path;
  }
  
  void clear() {
    pendingFilePath.value = null;
  }
}