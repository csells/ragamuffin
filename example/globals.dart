// Initialize logger
// ignore_for_file: avoid_print

import 'package:logging/logging.dart';
import 'package:ragamuffin/ragamuffin.dart';

void initializeLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) => print('${r.level.name}: ${r.message}'));
}

EmbeddingRepository? _repository;
EmbeddingRepository get repository {
  if (_repository == null) {
    _repository = EmbeddingRepository('ragamuffin.db');
    _repository!.initialize();
  }
  return _repository!;
}
