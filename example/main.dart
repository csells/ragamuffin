// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:developer' as dev;
import 'dart:io';

import 'package:args/command_runner.dart';
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

  final runner =
      CommandRunner<void>('ragamuffin', 'A CLI RAG tool for querying documents')
        ..addCommand(_CreateCommand())
        ..addCommand(_UpdateCommand())
        ..addCommand(_ChatCommand())
        ..addCommand(_ListCommand())
        ..addCommand(_DeleteCommand());

  try {
    await runner.run(argv);
  } on Exception catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }

  exit(0); // otherwise the async calls can cause the process to hang
}

void _requireApiKey() {
  if (openAiKey.isEmpty) {
    throw UsageException(
      'export OPENAI_API_KEY before running.',
      'Missing required environment variable',
    );
  }
}

class _CreateCommand extends Command<void> {
  _CreateCommand() {
    argParser.addFlag('yes', abbr: 'y', help: 'Skip confirmation prompt');
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a new vault from files in a directory';

  @override
  Future<void> run() async {
    print('DEBUG: CreateCommand.run() started');
    _requireApiKey();
    print('DEBUG: API key check passed');

    if (argResults!.rest.length < 2) {
      usageException('Usage: create <name> <file|dir>');
    }

    final name = argResults!.rest[0];
    final root = argResults!.rest[1];
    final force = argResults!['yes'] as bool;

    print('DEBUG: About to call _createVault($name, $root, force: $force)');
    await _createVault(name, root, force: force);
    print('DEBUG: _createVault completed');
  }
}

class _UpdateCommand extends Command<void> {
  @override
  String get name => 'update';

  @override
  String get description => 'Update an existing vault with file changes';

  @override
  Future<void> run() async {
    _requireApiKey();

    if (argResults!.rest.isEmpty) {
      usageException('Usage: update <name>');
    }

    final name = argResults!.rest[0];
    await _updateVault(name);
  }
}

class _ChatCommand extends Command<void> {
  @override
  String get name => 'chat';

  @override
  String get description => 'Start an interactive chat session with a vault';

  @override
  Future<void> run() async {
    _requireApiKey();

    if (argResults!.rest.isEmpty) {
      usageException('Usage: chat <name>');
    }

    final name = argResults!.rest[0];
    await _chatLoop(name);
  }
}

class _ListCommand extends Command<void> {
  @override
  String get name => 'list';

  @override
  String get description => 'List vaults or show details for a specific vault';

  @override
  Future<void> run() async {
    final filter = argResults!.rest.isNotEmpty ? argResults!.rest[0] : null;
    await _listVaults(filter);
  }
}

class _DeleteCommand extends Command<void> {
  _DeleteCommand() {
    argParser.addFlag('yes', abbr: 'y', help: 'Skip confirmation prompt');
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete a vault and all its chunks';

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('Usage: delete <name>');
    }

    final name = argResults!.rest[0];
    final force = argResults!['yes'] as bool;
    await _deleteVault(name, force: force);
  }
}

Future<void> _createVault(
  String name,
  String root, {
  required bool force,
}) async {
  print(
    'DEBUG: _createVault started with name=$name, root=$root, force=$force',
  );

  if (!force) {
    print('DEBUG: force=false, asking for confirmation');
    stdout.write(
      '⚠️  Your files will be sent to OpenAI to generate embeddings.\n'
      'Continue? (y/N) ',
    );
    final ans = stdin.readLineSync()?.trim().toLowerCase();
    if (ans != 'y' && ans != 'yes') {
      stdout.writeln('Aborted.');
      exit(0);
    }
  } else {
    print('DEBUG: force=true, skipping confirmation');
  }

  print('DEBUG: About to call _repository.createVault');
  try {
    final vault = await _repository.createVault(name, root);
    print('DEBUG: createVault succeeded, about to call syncVault');
    final result = await _repository.syncVault(vault.name);
    print('DEBUG: syncVault completed');
    print('Vault "$name" created → added: ${result['added']} chunks');
  } on Exception catch (ex) {
    print('DEBUG: Exception caught: $ex');
    stderr.writeln('Error: Vault "$name": $ex');
    exit(1);
  }
  print('DEBUG: _createVault finished');
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
