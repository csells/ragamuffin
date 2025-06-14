// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:developer' as dev;
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';
import 'package:ragamuffin/ragamuffin.dart';

final openAiKey = Platform.environment['OPENAI_API_KEY'] ?? '';

// Initialize logger
void _setupLogging(bool enable) {
  Logger.root.level = enable ? Level.ALL : Level.OFF;
  Logger.root.onRecord.listen((record) {
    dev.log('${record.level.name}: ${record.message}');
  });
}

final _logger = Logger('ragamuffin');
final _repository = EmbeddingRepository('ragamuffin.db');

Future<void> main(List<String> argv) async {
  _repository.initialize();
  _setupLogging(false);

  if (argv.isEmpty) {
    stderr.writeln(
      'Usage:\n'
      '  create <name> <file|dir>   [--yes]\n'
      '  update <name>\n'
      '  chat   <name>\n'
      '  list   [name]\n'
      '  delete <name> [--yes]',
    );
    exit(64);
  }

  final command = argv[0];
  final args = argv.sublist(1);

  // Commands that require OpenAI API key
  const apiCommands = {'create', 'update', 'chat'};
  if (apiCommands.contains(command) && openAiKey.isEmpty) {
    stderr.writeln('export OPENAI_API_KEY before running.');
    exit(64);
  }

  switch (command) {
    case 'create':
      if (args.length < 2) exit(64);
      await _createVault(args[0], args[1], force: args.contains('--yes'));
    case 'update':
      if (args.isEmpty) exit(64);
      await _updateVault(args[0]);
    case 'chat':
      if (args.isEmpty) exit(64);
      await _chatLoop(args[0]);
    case 'list':
      await _listVaults(args.isNotEmpty ? args[0] : null);
    case 'delete':
      if (args.isEmpty) exit(64);
      await _deleteVault(args[0], force: args.contains('--yes'));
    default:
      stderr.writeln('Unknown command: $command');
      stderr.writeln(
        'Usage:\n'
        '  create <name> <file|dir>   [--yes]\n'
        '  update <name>\n'
        '  chat   <name>\n'
        '  list   [name]\n'
        '  delete <name> [--yes]',
      );
      exit(64);
  }

  exit(0); // otherwise the async calls can cause the process to hang
}

Future<void> _createVault(
  String name,
  String root, {
  required bool force,
}) async {
  if (!force) {
    stdout.write(
      '⚠️  Your files will be sent to OpenAI to generate embeddings.\n'
      'Continue? (y/N) ',
    );
    final ans = stdin.readLineSync()?.trim().toLowerCase();
    if (ans != 'y' && ans != 'yes') {
      stdout.writeln('Aborted.');
      exit(0);
    }
  }

  try {
    final vault = await _repository.createVault(name, root);
    final result = await _repository.syncVault(vault.name);
    print('Vault "$name" created → added: ${result['added']} chunks');
  } on Exception catch (ex) {
    stderr.writeln('Error: Vault "$name": $ex');
    exit(1);
  }
}

Future<void> _updateVault(String name) async {
  final vault = await _repository.getVault(name);
  if (vault == null) {
    stderr.writeln('No vault named "$name". Run create command first.');
    exit(1);
  }
  final result = await _repository.syncVault(vault.name);
  print(
    'Vault "$name" updated → '
    'added: ${result['added']}, deleted: ${result['deleted']}',
  );
}

Future<void> _deleteVault(String name, {required bool force}) async {
  final vault = await _repository.getVault(name);
  if (vault == null) {
    stderr.writeln('No vault named "$name".');
    exit(1);
  }

  if (!force) {
    stdout.write(
      '⚠️  This will permanently delete vault "$name" and all its chunks.\n'
      'Continue? (y/N) ',
    );
    final ans = stdin.readLineSync()?.trim().toLowerCase();
    if (ans != 'y' && ans != 'yes') {
      stdout.writeln('Aborted.');
      exit(0);
    }
  }

  await _repository.deleteVault(name);
  print('Vault "$name" deleted.');
}

Future<void> _listVaults(String? filter) async {
  final vaultInfos = await _repository.getVaultInfo(filter);

  if (vaultInfos.isEmpty) {
    stderr.writeln(filter == null ? 'No vaults.' : 'No vault named "$filter".');
    return;
  }

  for (final info in vaultInfos) {
    print('\n🗄️  ${info.vault.name}  →  ${info.vault.rootPath}');
    if (info.markdownFiles.isEmpty) {
      print('   (no *.md)');
    } else {
      for (final file in info.markdownFiles) {
        print('   • $file');
      }
    }
  }
}

Future<void> _chatLoop(String name) async {
  final vault = await _repository.getVault(name);
  if (vault == null) {
    stderr.writeln('No vault named "$name".');
    exit(1);
  }

  if (await _repository.isVaultStale(vault.id, vault.rootPath)) {
    stdout.writeln(
      '\x1B[33m⚠️  Vault "$name" may be out-of-date. '
      'Run: dart run ragamuffin.dart --update $name\x1B[0m',
    );
  }

  final chunks = await _repository.getChunks(vault.id);

  // Initialize the chat agent with tools
  final chatAgent = ChatAgent(_repository, chunks);
  var history = <Message>[];

  void showHelp() {
    stdout.writeln('\n💬  Available commands:');
    stdout.writeln('    /help   - Show this help message');
    stdout.writeln('    /exit   - End the chat session');
    stdout.writeln('    /quit   - End the chat session');
    stdout.writeln('    /debug  - Toggle debug logging');
  }

  stdout.writeln('\n💬  Chat started. Type /help for available commands.');
  showHelp();

  while (true) {
    stdout.write('\n> ');
    final q = stdin.readLineSync()?.trim();
    if (q == null) continue;

    if (q.startsWith('/')) {
      final cmd = q.toLowerCase();
      switch (cmd) {
        case '/exit':
        case '/quit':
          stdout.writeln('\n👋  Goodbye!');
          return;
        case '/debug':
          final wasEnabled = _logger.level != Level.OFF;
          _setupLogging(!wasEnabled);
          stdout.writeln(
            '\n🔧  Debug logging ${wasEnabled ? "disabled" : "enabled"}',
          );
          continue;
        case '/help':
          showHelp();
          continue;
        default:
          stdout.writeln('\n❌  Unknown command: $cmd');
          stdout.writeln('    Type /help for available commands');
          continue;
      }
    }

    // Let dartantic_ai handle everything automatically
    _logger.fine('Sending query to agent: $q');
    final response = await chatAgent.run(q, messages: history);
    print('\n🤖  ${response.output}');

    // dartantic_ai automatically manages conversation state
    history = response.messages;
  }
}
