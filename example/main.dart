// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';
import 'package:ragamuffin/ragamuffin.dart';

/*──────────────────────  CONFIG  ──────────────────────*/

final openAiKey = Platform.environment['OPENAI_API_KEY'] ?? '';

// Initialize logger
void _setupLogging(bool enable) {
  Logger.root.level = enable ? Level.ALL : Level.OFF;
  Logger.root.onRecord.listen((record) {
    dev.log('${record.level.name}: ${record.message}');
  });
}

final _logger = Logger('ragamuffin');

/*──────────────────────  REPOSITORY  ─────────────────────*/

final repository = EmbeddingRepository('ragamuffin.db');

/*──────────────────────  MAIN  ────────────────────────*/

Future<void> main(List<String> argv) async {
  if (openAiKey.isEmpty) {
    stderr.writeln('export OPENAI_API_KEY before running.');
    exit(64);
  }
  repository.initialize();

  // Initialize logging as disabled by default
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

/*──────────────────  CREATE & UPDATE  ─────────────────*/

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
    final vault = await repository.createVault(name, root);
    await _syncVault(vault.name, vault.rootPath);
  } on Exception catch (ex) {
    stderr.writeln('Error: Vault "$name": $ex');
    exit(1);
  }
}

Future<void> _updateVault(String name) async {
  final vault = await repository.getVault(name);
  if (vault == null) {
    stderr.writeln('No vault named "$name". Run create command first.');
    exit(1);
  }
  await _syncVault(vault.name, vault.rootPath);
}

/*────────────────────────  DELETE  ──────────────────────*/

Future<void> _deleteVault(String name, {required bool force}) async {
  final vault = await repository.getVault(name);
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

  await repository.deleteVault(name);
  print('Vault "$name" deleted.');
}

/*──────────────  INDEX / SYNC SHARED LOGIC  ───────────*/

Future<void> _syncVault(String name, String root) async {
  final vault = await repository.getVault(name);
  if (vault == null) {
    throw ArgumentError('No vault named "$name"');
  }

  stdout.write('Scanning files...\n');
  final disk = <String, String>{}; // hash -> text
  final fileChunks = <String, List<String>>{}; // file -> chunks
  final files = repository
      .walkDirectory(root)
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList();

  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    final relativePath = f.path
        .replaceFirst(root, '')
        .replaceFirst(RegExp('^/+'), '');
    stdout.write('  (${i + 1}/${files.length}) $relativePath... ');
    final chunks = repository.chunkText(await f.readAsString());
    fileChunks[relativePath] = chunks;
    for (final piece in chunks) {
      disk[sha256.convert(utf8.encode(piece)).toString()] = piece;
    }
    stdout.writeln('${chunks.length} chunks');
  }
  stdout.writeln('Scan complete.');

  final dbHashes = await repository.getChunkHashes(vault.id);

  var added = 0;
  var deleted = 0;
  final toAdd = disk.entries.where((e) => !dbHashes.contains(e.key)).toList();

  if (toAdd.isNotEmpty) {
    stdout.write('\nEmbedding ${toAdd.length} chunks...\n');

    // Create a map of hash -> file for each chunk
    final chunkToFile = <String, String>{};
    for (final entry in fileChunks.entries) {
      for (final chunk in entry.value) {
        chunkToFile[sha256.convert(utf8.encode(chunk)).toString()] = entry.key;
      }
    }

    // Keep track of progress sequentially
    var currentChunk = 0;
    String? currentFile;
    for (final entry in toAdd) {
      currentChunk++;
      final file = chunkToFile[entry.key]!;
      if (file != currentFile) {
        if (currentFile != null) stdout.write('\n');
        stdout.write('  ($currentChunk/${toAdd.length}) $file... ');
        currentFile = file;
      }

      final vec = await repository.createEmbedding(entry.value);
      await repository.addChunk(
        vaultId: vault.id,
        text: entry.value,
        vector: vec,
      );
      added++;
      stdout.write('.');
    }
    stdout.writeln('\nEmbedding complete.');
  }

  for (final hash in dbHashes.difference(disk.keys.toSet())) {
    await repository.deleteChunk(hash, vault.id);
    deleted++;
  }
  print('\nVault "$name" sync  → added: $added  deleted: $deleted');
}

/*────────────────────────  LIST  ──────────────────────*/

Future<void> _listVaults(String? filter) async {
  final vaults = await repository.getAllVaults(filter);

  if (vaults.isEmpty) {
    stderr.writeln(filter == null ? 'No vaults.' : 'No vault named "$filter".');
    return;
  }
  for (final vault in vaults) {
    print('\n🗄️  ${vault.name}  →  ${vault.rootPath}');
    final files = repository
        .walkDirectory(vault.rootPath)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map(
          (f) => f.path
              .replaceFirst(vault.rootPath, '')
              .replaceFirst(RegExp('^/+'), ''),
        )
        .toList();
    if (files.isEmpty) print('   (no *.md)');
    for (final f in files) {
      print('   • $f');
    }
  }
}

/*────────────────────────  CHAT  ──────────────────────*/

Future<void> _chatLoop(String name) async {
  final vault = await repository.getVault(name);
  if (vault == null) {
    stderr.writeln('No vault named "$name".');
    exit(1);
  }

  if (await repository.isVaultStale(vault.id, vault.rootPath)) {
    stdout.writeln(
      '\x1B[33m⚠️  Vault "$name" may be out-of-date. '
      'Run: dart run ragamuffin.dart --update $name\x1B[0m',
    );
  }

  final chunks = await repository.getChunks(vault.id);
  final chunkData = chunks
      .map((c) => _Chunk(c.text, c.vector))
      .toList(growable: false);

  // Initialize the dartantic_ai agent with tools
  _initializeAgent(chunkData);

  var msgs = <Message>[];

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
    final response = await _chatAgent.run(q, messages: msgs);
    print('\n🤖  ${response.output}');

    // dartantic_ai automatically manages conversation state
    msgs = response.messages;
  }
}

/*──────────────────  UTILITIES  ──────────────────────*/

// Global agent and tool for chat functionality
late Agent _chatAgent;
late Tool _retrieveTool;

void _initializeAgent(List<_Chunk> chunks) {
  _retrieveTool = Tool(
    name: 'retrieve_chunks',
    description: 'Search for documents in the vector store',
    inputType: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'The search query'},
      },
      'required': ['query'],
    }.toSchema(),
    onCall: (input) async {
      final query = input['query'] as String;
      final vecQ = await repository.createEmbedding(query);
      final hits = _rank(chunks, vecQ, 4).map((c) => c.text).join('\n---\n');
      return {'snippets': hits};
    },
  );

  _chatAgent = Agent(
    'openai:gpt-4o-mini',
    tools: [_retrieveTool],
    systemPrompt: '''
You are a helpful assistant that answers questions based ONLY on the content in Chris's vault. 
When asked a question:
1. First, use retrieve_chunks to search for relevant information in the vault
2. Then, answer the question using ONLY the information found in the vault
3. If the vault doesn't contain relevant information, say so clearly
4. Do not make up or infer information not present in the vault
5. Do not use any external knowledge unless it's explicitly mentioned in the vault''',
  );
}

Iterable<_Chunk> _rank(List<_Chunk> all, List<double> q, int k) {
  final scored =
      all
          .map((c) => MapEntry(c, repository.cosineSimilarity(c.vec, q)))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  return scored.take(k).map((e) => e.key);
}

class _Chunk {
  _Chunk(this.text, this.vec);
  final String text;
  final List<double> vec;
}
