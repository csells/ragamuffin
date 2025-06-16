import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';
import 'package:sqlite3/sqlite3.dart';

import 'embedding_chunk.dart';
import 'typed_database.dart';
import 'vault.dart';
import 'vault_info.dart';

Logger? _loggerInstance;
Logger get _logger => _loggerInstance ??= Logger('ragamuffin');

/// Repository for managing embeddings and vector operations
class EmbeddingRepository {
  /// Creates a new embedding repository with the specified database path.
  EmbeddingRepository(this._dbPath, [this._agent]);

  final String _dbPath;
  final Agent? _agent;
  late final Database _db;

  /// Initialize the database and create tables
  void initialize() {
    _db = sqlite3.open(_dbPath);
    _createTables();
  }

  void _createTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS vaults (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        name      TEXT UNIQUE,
        root_path TEXT
      );
    ''');
    _db.execute('''
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

  /// Create a new vault
  Future<Vault> createVault(String name, String rootPath) async {
    if (await vaultExists(name)) {
      throw Exception('Vault "$name" already exists');
    }

    _db.execute('INSERT INTO vaults (name, root_path) VALUES (?, ?)', [
      name,
      rootPath,
    ]);

    final result = _db.select(
      'SELECT id, name, root_path FROM vaults WHERE name = ?',
      [name],
    ).first;

    return Vault.fromMap(result);
  }

  /// Get a vault by name
  Future<Vault?> getVault(String name) async {
    final query = TypedQuery(
      'SELECT id, name, root_path FROM vaults WHERE name = ?',
      [name],
      Vault.fromMap,
    );

    return _db.selectSingleTyped(query);
  }

  /// Check if a vault exists
  Future<bool> vaultExists(String name) async {
    final result = _db.select('SELECT 1 FROM vaults WHERE name = ?', [name]);
    return result.isNotEmpty;
  }

  /// Get all vaults, optionally filtered by name
  Future<List<Vault>> getAllVaults([String? filter]) async {
    final query = filter == null
        ? const TypedQuery(
            'SELECT id, name, root_path FROM vaults',
            <Object?>[],
            Vault.fromMap,
          )
        : TypedQuery('SELECT id, name, root_path FROM vaults WHERE name = ?', [
            filter,
          ], Vault.fromMap);

    return _db.selectTyped(query);
  }

  /// Delete a vault and all its chunks
  Future<void> deleteVault(String name) async {
    final vault = await getVault(name);
    if (vault == null) {
      throw ArgumentError('No vault named "$name"');
    }

    // Delete all chunks first (due to foreign key constraint)
    _db.execute('DELETE FROM chunks WHERE vault_id = ?', [vault.id]);

    // Then delete the vault
    _db.execute('DELETE FROM vaults WHERE id = ?', [vault.id]);
  }

  /// Add a chunk to the vault
  Future<void> addChunk({
    required int vaultId,
    required String text,
    required Float64List vector,
  }) async {
    final hash = sha256.convert(utf8.encode(text)).toString();

    _db.execute(
      'INSERT INTO chunks (vault_id, hash, text, vec) VALUES (?,?,?,?)',
      [vaultId, hash, text, jsonEncode(vector)],
    );
  }

  /// Get all chunks for a vault
  Future<List<EmbeddingChunk>> getChunks(int vaultId) async {
    final query = TypedQuery(
      'SELECT id, vault_id, hash, text, vec FROM chunks WHERE vault_id = ?',
      [vaultId],
      EmbeddingChunk.fromMap,
    );

    return _db.selectTyped(query);
  }

  /// Get all hashes for chunks in a vault
  Future<Set<String>> getChunkHashes(int vaultId) async {
    final result = _db.select('SELECT hash FROM chunks WHERE vault_id = ?', [
      vaultId,
    ]);

    return result.map((r) => r['hash'] as String).toSet();
  }

  /// Delete a chunk by hash and vault ID
  Future<void> deleteChunk(String hash, int vaultId) async {
    _db.execute('DELETE FROM chunks WHERE hash = ? AND vault_id = ?', [
      hash,
      vaultId,
    ]);
  }

  /// Generate embedding for text using dartantic_ai
  Future<Float64List> createEmbedding(String text) async {
    final agent = _agent ?? Agent('openai');
    final embedding = await agent.createEmbedding(
      text,
      type: EmbeddingType.document,
    );
    return Float64List.fromList(embedding);
  }

  /// Rank chunks by similarity to query vector
  List<EmbeddingChunk> rankChunks(
    List<EmbeddingChunk> chunks,
    Float64List queryVector,
    int topK,
  ) {
    final scored =
        chunks
            .map(
              (c) => MapEntry(c, Agent.cosineSimilarity(c.vector, queryVector)),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return scored.take(topK).map((e) => e.key).toList();
  }

  /// Text chunking with token estimation
  List<String> chunkText(String text) {
    final sents = text.split(RegExp(r'(?<=[.?!])\s+'));
    final out = <String>[];
    final buf = StringBuffer();
    var currentTokens = 0;
    const maxTokens = 6000;

    for (final s in sents) {
      final sentTokens = _estimateTokens(s);
      if (currentTokens + sentTokens > maxTokens) {
        if (buf.isNotEmpty) {
          final chunk = buf.toString().trim();
          if (_estimateTokens(chunk) > maxTokens) {
            out.addAll(_splitLongChunk(chunk, maxTokens));
          } else {
            out.add(chunk);
          }
          buf.clear();
          currentTokens = 0;
        }
        if (sentTokens > maxTokens) {
          out.addAll(_splitLongChunk(s, maxTokens));
          continue;
        }
      }
      buf.write('$s ');
      currentTokens += sentTokens;
    }

    if (buf.isNotEmpty) {
      final chunk = buf.toString().trim();
      if (_estimateTokens(chunk) > maxTokens) {
        out.addAll(_splitLongChunk(chunk, maxTokens));
      } else {
        out.add(chunk);
      }
    }

    return out;
  }

  List<String> _splitLongChunk(String chunk, int maxTokens) {
    final words = chunk.split(RegExp(r'\s+'));
    final out = <String>[];
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

    return out;
  }

  int _estimateTokens(String text) => (text.length / 3).ceil();

  /// Walk directory and return file system entities
  Iterable<FileSystemEntity> walkDirectory(String start) sync* {
    final t = FileSystemEntity.typeSync(start);
    if (t == FileSystemEntityType.file) {
      yield File(start);
    } else if (t == FileSystemEntityType.directory) {
      yield* Directory(start).listSync(recursive: true, followLinks: false);
    }
  }

  /// Check if vault is stale (disk content differs from database)
  Future<bool> isVaultStale(int vaultId, String rootPath) async {
    final diskHashes = <String>{};
    for (final f in walkDirectory(
      rootPath,
    ).whereType<File>().where((f) => f.path.endsWith('.md'))) {
      final content = await f.readAsString();
      for (final chunk in chunkText(content)) {
        diskHashes.add(sha256.convert(utf8.encode(chunk)).toString());
      }
    }

    final dbHashes = await getChunkHashes(vaultId);
    return diskHashes.length != dbHashes.length ||
        !diskHashes.containsAll(dbHashes);
  }

  /// Synchronize a vault with its file system directory
  Future<Map<String, int>> syncVault(String name) async {
    final vault = await getVault(name);
    if (vault == null) {
      throw ArgumentError('No vault named "$name"');
    }

    _logger.log(Level.INFO, 'Scanning files...');
    final disk = <String, String>{}; // hash -> text
    final fileChunks = <String, List<String>>{}; // file -> chunks
    final files = walkDirectory(
      vault.rootPath,
    ).whereType<File>().where((f) => f.path.endsWith('.md')).toList();

    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final relativePath = f.path
          .replaceFirst(vault.rootPath, '')
          .replaceFirst(RegExp('^/+'), '');
      _logger.log(Level.INFO, '  (${i + 1}/${files.length}) $relativePath... ');
      final chunks = chunkText(await f.readAsString());
      fileChunks[relativePath] = chunks;
      for (final piece in chunks) {
        disk[sha256.convert(utf8.encode(piece)).toString()] = piece;
      }
      _logger.log(Level.INFO, '${chunks.length} chunks');
    }
    _logger.log(Level.INFO, 'Scan complete.');

    final dbHashes = await getChunkHashes(vault.id);

    var added = 0;
    var deleted = 0;
    final toAdd = disk.entries.where((e) => !dbHashes.contains(e.key)).toList();

    if (toAdd.isNotEmpty) {
      _logger.log(Level.INFO, '\nEmbedding ${toAdd.length} chunks...\n');

      // Create a map of hash -> file for each chunk
      final chunkToFile = <String, String>{};
      for (final entry in fileChunks.entries) {
        for (final chunk in entry.value) {
          chunkToFile[sha256.convert(utf8.encode(chunk)).toString()] =
              entry.key;
        }
      }

      // Keep track of progress sequentially
      var currentChunk = 0;
      String? currentFile;
      for (final entry in toAdd) {
        currentChunk++;
        final file = chunkToFile[entry.key]!;
        if (file != currentFile) {
          _logger.log(
            Level.INFO,
            '  ($currentChunk/${toAdd.length}) $file... ',
          );
          currentFile = file;
        }

        final vector = await createEmbedding(entry.value);
        await addChunk(vaultId: vault.id, text: entry.value, vector: vector);
        added++;
      }
      _logger.log(Level.INFO, '\nEmbedding complete.');
    }

    final toDelete = dbHashes.difference(disk.keys.toSet());
    for (final hash in toDelete) {
      await deleteChunk(hash, vault.id);
      deleted++;
    }

    _logger.log(
      Level.INFO,
      '\nVault "$name" sync  → added: $added  deleted: $deleted',
    );
    return {'added': added, 'deleted': deleted};
  }

  /// Get vault information with file listings
  Future<List<VaultInfo>> getVaultInfo([String? filter]) async {
    final vaults = await getAllVaults(filter);
    final result = <VaultInfo>[];

    for (final vault in vaults) {
      final files = walkDirectory(vault.rootPath)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .map(
            (f) => f.path
                .replaceFirst(vault.rootPath, '')
                .replaceFirst(RegExp('^/+'), ''),
          )
          .toList();

      result.add(VaultInfo(vault: vault, markdownFiles: files));
    }

    return result;
  }

  /// Close the database connection
  void close() {
    _db.dispose();
  }
}
