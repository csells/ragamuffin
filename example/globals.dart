// Initialize logger
// ignore_for_file: avoid_print

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';
import 'package:ragamuffin/ragamuffin.dart';

void initLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) => print('${r.level.name}: ${r.message}'));
}

EmbeddingRepository? _repository;
void initRepository(String model) {
  assert(_repository == null, 'Repository already initialized.');
  final agent = Agent(model);
  _repository = EmbeddingRepository('ragamuffin.db', agent);
  _repository!.initialize();
}

EmbeddingRepository get repository {
  assert(_repository != null, 'Call initRepository first.');
  return _repository!;
}

void closeRepository() => _repository?.close();
