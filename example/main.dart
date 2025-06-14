// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';
import 'package:sqlite3/sqlite3.dart';

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

/*──────────────────────  DB INIT  ─────────────────────*/

final db = sqlite3.open('ragamuffin.db');

void _initDb() {
  db.execute('''
    CREATE TABLE IF NOT EXISTS vaults (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      name      TEXT UNIQUE,
      root_path TEXT
    );
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS chunks (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      vault_id  INTEGER,
      hash      TEXT,
      text      TEXT,
      vec       BLOB,
      UNIQUE(hash, vault_id)
    );
  ''');
}

/*──────────────────────  MAIN  ────────────────────────*/

Future<void> main(List<String> argv) async {
  if (openAiKey.isEmpty) {
    stderr.writeln('export OPENAI_API_KEY before running.');
    exit(64);
  }
  _initDb();

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
  if (db.select('SELECT 1 FROM vaults WHERE name = ?', [name]).isNotEmpty) {
    stderr.writeln('Vault "$name" already exists. Use --update.');
    exit(1);
  }
  db.execute('INSERT INTO vaults (name, root_path) VALUES (?, ?)', [
    name,
    root,
  ]);
  await _syncVault(name, root);
}

Future<void> _updateVault(String name) async {
  final row = db.select('SELECT root_path FROM vaults WHERE name = ?', [
    name,
  ]).firstOrNull;
  if (row == null) {
    stderr.writeln('No vault named "$name". Run --create first.');
    exit(1);
  }
  await _syncVault(name, row['root_path'] as String);
}

/*────────────────────────  DELETE  ──────────────────────*/

Future<void> _deleteVault(String name, {required bool force}) async {
  final row = db.select('SELECT id FROM vaults WHERE name = ?', [
    name,
  ]).firstOrNull;
  if (row == null) {
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

  final vaultId = row['id'] as int;

  // Delete all chunks first (due to foreign key constraint)
  db.execute('DELETE FROM chunks WHERE vault_id = ?', [vaultId]);

  // Then delete the vault
  db.execute('DELETE FROM vaults WHERE id = ?', [vaultId]);

  print('Vault "$name" deleted.');
}

/*──────────────  INDEX / SYNC SHARED LOGIC  ───────────*/

Future<void> _syncVault(String name, String root) async {
  final vaultId =
      db.select('SELECT id FROM vaults WHERE name = ?', [name]).first['id']
          as int;

  stdout.write('Scanning files...\n');
  final disk = <String, String>{}; // hash -> text
  final fileChunks = <String, List<String>>{}; // file -> chunks
  final files = _walk(
    root,
  ).whereType<File>().where((f) => f.path.endsWith('.md')).toList();

  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    final relativePath = f.path
        .replaceFirst(root, '')
        .replaceFirst(RegExp('^/+'), '');
    stdout.write('  (${i + 1}/${files.length}) $relativePath... ');
    final chunks = _chunkText(await f.readAsString());
    fileChunks[relativePath] = chunks;
    for (final piece in chunks) {
      disk[sha256.convert(utf8.encode(piece)).toString()] = piece;
    }
    stdout.writeln('${chunks.length} chunks');
  }
  stdout.writeln('Scan complete.');

  final dbHashes = db
      .select('SELECT hash FROM chunks WHERE vault_id = ?', [vaultId])
      .map((r) => r['hash'] as String)
      .toSet();

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

    // Get all files that have chunks to add
    final filesToProcess = <String>{};
    for (final entry in toAdd) {
      filesToProcess.add(chunkToFile[entry.key]!);
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

      final vec = await _embed(entry.value);
      db.execute(
        'INSERT INTO chunks (vault_id, hash, text, vec) VALUES (?,?,?,?)',
        [vaultId, entry.key, entry.value, jsonEncode(vec)],
      );
      added++;
      stdout.write('.');
    }
    stdout.writeln('\nEmbedding complete.');
  }

  for (final hash in dbHashes.difference(disk.keys.toSet())) {
    db.execute('DELETE FROM chunks WHERE hash = ? AND vault_id = ?', [
      hash,
      vaultId,
    ]);
    deleted++;
  }
  print('\nVault "$name" sync  → added: $added  deleted: $deleted');
}

/*────────────────────────  LIST  ──────────────────────*/

Future<void> _listVaults(String? filter) async {
  final rows = filter == null
      ? db.select('SELECT name, root_path FROM vaults')
      : db.select('SELECT name, root_path FROM vaults WHERE name = ?', [
          filter,
        ]);

  if (rows.isEmpty) {
    stderr.writeln(filter == null ? 'No vaults.' : 'No vault named "$filter".');
    return;
  }
  for (final r in rows) {
    final name = r['name'] as String;
    final root = r['root_path'] as String;
    print('\n🗄️  $name  →  $root');
    final files = _walk(root)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map(
          (f) => f.path.replaceFirst(root, '').replaceFirst(RegExp('^/+'), ''),
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
  final row = db.select('SELECT id, root_path FROM vaults WHERE name = ?', [
    name,
  ]).firstOrNull;
  if (row == null) {
    stderr.writeln('No vault named "$name".');
    exit(1);
  }
  final vaultId = row['id'] as int;
  final root = row['root_path'] as String;

  if (_vaultStale(vaultId, root)) {
    stdout.writeln(
      '\x1B[33m⚠️  Vault "$name" may be out-of-date. '
      'Run: dart run ragamuffin.dart --update $name\x1B[0m',
    );
  }

  final chunks = db
      .select('SELECT text, vec FROM chunks WHERE vault_id = ?', [vaultId])
      .map(
        (r) => _Chunk(
          r['text'] as String,
          (jsonDecode(r['vec'] as String) as List)
              .cast<num>()
              .map((n) => n.toDouble())
              .toList(),
        ),
      )
      .toList(growable: false);

  // Initialize the dartantic_ai agent with tools
  _initializeAgent(chunks);

  var msgs = <Message>[
    Message(
      role: MessageRole.system,
      content: [
        const TextPart('''
You are a helpful assistant that answers questions based ONLY on the content in Chris's vault. 
When asked a question:
1. First, use retrieve_chunks to search for relevant information in the vault
2. Then, answer the question using ONLY the information found in the vault
3. If the vault doesn't contain relevant information, say so clearly
4. Do not make up or infer information not present in the vault
5. Do not use any external knowledge unless it's explicitly mentioned in the vault'''),
      ],
    ),
  ];

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

bool _vaultStale(int vaultId, String root) {
  final diskHashes = <String>{};
  for (final f in _walk(
    root,
  ).whereType<File>().where((f) => f.path.endsWith('.md'))) {
    for (final t in _chunkText(File(f.path).readAsStringSync())) {
      diskHashes.add(sha256.convert(utf8.encode(t)).toString());
    }
  }
  final dbHashes = db
      .select('SELECT hash FROM chunks WHERE vault_id = ?', [vaultId])
      .map((r) => r['hash'] as String)
      .toSet();
  return diskHashes.length != dbHashes.length ||
      !diskHashes.containsAll(dbHashes);
}

/*──────────────────  UTILITIES  ──────────────────────*/

// Rough estimate: 1 token ≈ 3 chars for English text (more conservative)
int _estimateTokens(String text) => (text.length / 3).ceil();

List<String> _chunkText(String text) {
  final sents = text.split(RegExp(r'(?<=[.?!])\s+'));
  final out = <String>[];
  final buf = StringBuffer();
  var currentTokens = 0;
  const maxTokens = 6000; // More conservative limit

  for (final s in sents) {
    final sentTokens = _estimateTokens(s);
    if (currentTokens + sentTokens > maxTokens) {
      if (buf.isNotEmpty) {
        final chunk = buf.toString().trim();
        // Safety check - if our estimate was wrong, split the chunk
        if (_estimateTokens(chunk) > maxTokens) {
          final words = chunk.split(RegExp(r'\s+'));
          final wordBuf = StringBuffer();
          var wordTokens = 0;
          for (final word in words) {
            final wordTokenCount = _estimateTokens(word);
            if (wordTokens + wordTokenCount > maxTokens) {
              if (wordBuf.isNotEmpty) {
                out.add(wordBuf.toString().trim());
                wordBuf.clear();
                wordTokens = 0;
              }
            }
            wordBuf.write('$word ');
            wordTokens += wordTokenCount;
          }
          if (wordBuf.isNotEmpty) {
            out.add(wordBuf.toString().trim());
          }
        } else {
          out.add(chunk);
        }
        buf.clear();
        currentTokens = 0;
      }
      // If a single sentence is too long, split it into smaller pieces
      if (sentTokens > maxTokens) {
        final words = s.split(RegExp(r'\s+'));
        final wordBuf = StringBuffer();
        var wordTokens = 0;
        for (final word in words) {
          final wordTokenCount = _estimateTokens(word);
          if (wordTokens + wordTokenCount > maxTokens) {
            if (wordBuf.isNotEmpty) {
              out.add(wordBuf.toString().trim());
              wordBuf.clear();
              wordTokens = 0;
            }
          }
          wordBuf.write('$word ');
          wordTokens += wordTokenCount;
        }
        if (wordBuf.isNotEmpty) {
          out.add(wordBuf.toString().trim());
        }
        continue;
      }
    }
    buf.write('$s ');
    currentTokens += sentTokens;
  }
  if (buf.isNotEmpty) {
    final chunk = buf.toString().trim();
    // Final safety check
    if (_estimateTokens(chunk) > maxTokens) {
      final words = chunk.split(RegExp(r'\s+'));
      final wordBuf = StringBuffer();
      var wordTokens = 0;
      for (final word in words) {
        final wordTokenCount = _estimateTokens(word);
        if (wordTokens + wordTokenCount > maxTokens) {
          if (wordBuf.isNotEmpty) {
            out.add(wordBuf.toString().trim());
            wordBuf.clear();
            wordTokens = 0;
          }
        }
        wordBuf.write('$word ');
        wordTokens += wordTokenCount;
      }
      if (wordBuf.isNotEmpty) {
        out.add(wordBuf.toString().trim());
      }
    } else {
      out.add(chunk);
    }
  }
  return out;
}

Iterable<FileSystemEntity> _walk(String start) sync* {
  final t = FileSystemEntity.typeSync(start);
  if (t == FileSystemEntityType.file) {
    yield File(start);
  } else if (t == FileSystemEntityType.directory) {
    yield* Directory(start).listSync(recursive: true, followLinks: false);
  }
}

Future<List<double>> _embed(String text) =>
    Agent('openai').createEmbedding(text, type: EmbeddingType.document);

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
      final vecQ = await _embed(query);
      final hits = _rank(chunks, vecQ, 4).map((c) => c.text).join('\n---\n');
      return {'snippets': hits};
    },
  );

  _chatAgent = Agent('openai:gpt-4o-mini', tools: [_retrieveTool]);
}

double _cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError('Vectors must have same length');
  }

  double dotProduct = 0;
  double normA = 0;
  double normB = 0;
  for (var i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dotProduct / (sqrt(normA) * sqrt(normB));
}

Iterable<_Chunk> _rank(List<_Chunk> all, List<double> q, int k) {
  final scored =
      all.map((c) => MapEntry(c, _cosineSimilarity(c.vec, q))).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  return scored.take(k).map((e) => e.key);
}

class _Chunk {
  _Chunk(this.text, this.vec);
  final String text;
  final List<double> vec;
}
