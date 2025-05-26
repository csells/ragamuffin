// dart pub add http args sqlite3 crypto vector_math
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

/*──────────────────────  CONFIG  ──────────────────────*/

const openAiKey = String.fromEnvironment('OPENAI_API_KEY');
const embedModel = 'text-embedding-3-small';
const chatModel = 'gpt-4o-mini';

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

  final argp = ArgParser()
    ..addFlag('create', negatable: false)
    ..addFlag('update', negatable: false)
    ..addFlag('chat', negatable: false)
    ..addFlag('list', negatable: false)
    ..addFlag('yes', negatable: false);
  final args = argp.parse(argv);

  final modes = [
    'create',
    'update',
    'chat',
    'list',
  ].where((m) => args[m]).toList();
  if (modes.length != 1) {
    stderr.writeln(
      'Usage:\n'
      '  --create <name> <file|dir>   [--yes]\n'
      '  --update <name>\n'
      '  --chat   <name>\n'
      '  --list   [name]',
    );
    exit(64);
  }

  switch (modes.first) {
    case 'create':
      if (argv.length < 3) exit(64);
      await _createVault(argv[1], argv[2], force: args['yes']);
      break;
    case 'update':
      if (argv.length < 2) exit(64);
      await _updateVault(argv[1]);
      break;
    case 'chat':
      if (argv.length < 2) exit(64);
      await _chatLoop(argv[1]);
      break;
    case 'list':
      await _listVaults(argv.length > 1 ? argv[1] : null);
  }
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

/*──────────────  INDEX / SYNC SHARED LOGIC  ───────────*/

Future<void> _syncVault(String name, String root) async {
  final vaultId =
      db.select('SELECT id FROM vaults WHERE name = ?', [name]).first['id']
          as int;

  final disk = <String, String>{}; // hash -> text
  for (final f in _walk(
    root,
  ).whereType<File>().where((f) => f.path.endsWith('.md'))) {
    for (final piece in _chunkText(await f.readAsString())) {
      disk[sha256.convert(utf8.encode(piece)).toString()] = piece;
    }
  }

  final dbHashes = db
      .select('SELECT hash FROM chunks WHERE vault_id = ?', [vaultId])
      .map((r) => r['hash'] as String)
      .toSet();

  int added = 0, deleted = 0;

  for (final entry in disk.entries) {
    if (dbHashes.contains(entry.key)) continue;
    final vec = await _embed(entry.value);
    db.execute(
      'INSERT INTO chunks (vault_id, hash, text, vec) VALUES (?,?,?,?)',
      [vaultId, entry.key, entry.value, jsonEncode(vec)],
    );
    added++;
  }
  for (final hash in dbHashes.difference(disk.keys.toSet())) {
    db.execute('DELETE FROM chunks WHERE hash = ? AND vault_id = ?', [
      hash,
      vaultId,
    ]);
    deleted++;
  }
  print('Vault "$name" sync  → added: $added  deleted: $deleted');
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
          (f) => f.path.replaceFirst(root, '').replaceFirst(RegExp(r'^/+'), ''),
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

  final msgs = [
    {
      'role': 'system',
      'content':
          'You answer from Chris\'s vault. Call retrieve_chunks when needed.',
    },
  ];

  while (true) {
    stdout.write('\n🙋‍♂️  > ');
    final q = stdin.readLineSync();
    if (q == null || q.toLowerCase() == 'exit') break;

    msgs.add({'role': 'user', 'content': q});
    final reply = await _chat(msgs);
    final choice = reply['choices'][0];

    if (choice['finish_reason'] == 'tool_calls') {
      final call = choice['message']['tool_calls'][0];
      final query =
          jsonDecode(call['function']['arguments'])['query'] as String;
      final vecQ = await _embed(query);
      final hits = _rank(chunks, vecQ, 4).map((c) => c.text).join('\n---\n');

      msgs
        ..add(choice['message'])
        ..add({
          'role': 'tool',
          'tool_call_id': call['id'],
          'name': 'retrieve_chunks',
          'content': jsonEncode({'snippets': hits}),
        });

      final cont = await _chat(msgs);
      print('\n🤖  ${cont['choices'][0]['message']['content']}');
      msgs.add(cont['choices'][0]['message']);
    } else {
      print('\n🤖  ${choice['message']['content']}');
      msgs.add(choice['message']);
    }
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

Iterable<FileSystemEntity> _walk(String start) sync* {
  final t = FileSystemEntity.typeSync(start);
  if (t == FileSystemEntityType.file) {
    yield File(start);
  } else if (t == FileSystemEntityType.directory) {
    yield* Directory(start).listSync(recursive: true, followLinks: false);
  }
}

List<String> _chunkText(String text) {
  final sents = text.split(RegExp(r'(?<=[.?!])\s+'));
  final out = <String>[];
  final buf = StringBuffer();
  for (final s in sents) {
    buf.write('$s ');
    if (buf.length > 500) {
      out.add(buf.toString().trim());
      buf.clear();
    }
  }
  if (buf.isNotEmpty) out.add(buf.toString().trim());
  return out;
}

Future<List<double>> _embed(String text) async {
  final res = await http.post(
    Uri.https('api.openai.com', '/v1/embeddings'),
    headers: {
      'Authorization': 'Bearer $openAiKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'model': embedModel, 'input': text}),
  );
  return (jsonDecode(res.body)['data'][0]['embedding'] as List)
      .cast<num>()
      .map((n) => n.toDouble())
      .toList();
}

Future<Map<String, dynamic>> _chat(List<Map<String, dynamic>> msgs) async {
  final body = {
    'model': chatModel,
    'messages': msgs,
    'tools': [
      {
        'type': 'function',
        'function': {
          'name': 'retrieve_chunks',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string'},
            },
            'required': ['query'],
          },
        },
      },
    ],
    'tool_choice': 'auto',
  };
  final res = await http.post(
    Uri.https('api.openai.com', '/v1/chat/completions'),
    headers: {
      'Authorization': 'Bearer $openAiKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode(body),
  );
  return jsonDecode(res.body);
}

double _cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError('Vectors must have same length');
  }

  double dotProduct = 0;
  double normA = 0;
  double normB = 0;
  for (int i = 0; i < a.length; i++) {
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
  final String text;
  final List<double> vec;
  _Chunk(this.text, this.vec);
}
