import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:ragamuffin/ragamuffin.dart';
import 'package:test/test.dart';

void main() {
  late EmbeddingRepository repository;
  late Directory tempDir;
  late String tempDbPath;

  // Helper function to convert list to Float64List
  Float64List vec(List<double> values) => Float64List.fromList(values);

  setUp(() async {
    // Create temporary directory and database for each test
    tempDir = await Directory.systemTemp.createTemp('ragamuffin_test_');
    tempDbPath = '${tempDir.path}/test.db';
    repository = EmbeddingRepository(tempDbPath);
    repository.initialize();
  });

  tearDown(() {
    // Clean up after each test
    repository.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Vault Operations', () {
    test('should create a new vault', () async {
      const name = 'test_vault';
      const rootPath = '/test/path';

      final vault = await repository.createVault(name, rootPath);

      expect(vault.name, equals(name));
      expect(vault.rootPath, equals(rootPath));
      expect(vault.id, isPositive);
    });

    test('should throw error when creating duplicate vault', () async {
      const name = 'test_vault';
      const rootPath = '/test/path';

      await repository.createVault(name, rootPath);

      expect(() => repository.createVault(name, rootPath), throwsException);
    });

    test('should get existing vault by name', () async {
      const name = 'test_vault';
      const rootPath = '/test/path';

      final created = await repository.createVault(name, rootPath);
      final retrieved = await repository.getVault(name);

      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals(created.id));
      expect(retrieved.name, equals(name));
      expect(retrieved.rootPath, equals(rootPath));
    });

    test('should return null for non-existent vault', () async {
      final vault = await repository.getVault('non_existent');
      expect(vault, isNull);
    });

    test('should check if vault exists', () async {
      const name = 'test_vault';
      const rootPath = '/test/path';

      expect(await repository.vaultExists(name), isFalse);

      await repository.createVault(name, rootPath);

      expect(await repository.vaultExists(name), isTrue);
    });

    test('should get all vaults', () async {
      await repository.createVault('vault1', '/path1');
      await repository.createVault('vault2', '/path2');

      final vaults = await repository.getAllVaults();

      expect(vaults, hasLength(2));
      expect(vaults.map((v) => v.name), containsAll(['vault1', 'vault2']));
    });

    test('should filter vaults by name', () async {
      await repository.createVault('vault1', '/path1');
      await repository.createVault('vault2', '/path2');

      final filtered = await repository.getAllVaults('vault1');

      expect(filtered, hasLength(1));
      expect(filtered.first.name, equals('vault1'));
    });

    test('should delete vault and its chunks', () async {
      const name = 'test_vault';
      const rootPath = '/test/path';

      final vault = await repository.createVault(name, rootPath);

      // Add a chunk to verify it gets deleted
      await repository.addChunk(
        vaultId: vault.id,
        text: 'test chunk',
        vector: vec([1.0, 2.0, 3.0]),
      );

      await repository.deleteVault(name);

      expect(await repository.getVault(name), isNull);
      final chunks = await repository.getChunks(vault.id);
      expect(chunks, isEmpty);
    });

    test('should throw error when deleting non-existent vault', () async {
      expect(() => repository.deleteVault('non_existent'), throwsArgumentError);
    });
  });

  group('Chunk Operations', () {
    late Vault testVault;

    setUp(() async {
      testVault = await repository.createVault('test_vault', '/test/path');
    });

    test('should add chunk to vault', () async {
      const text = 'This is a test chunk';
      final vector = vec([1.0, 2.0, 3.0, 4.0]);

      await repository.addChunk(
        vaultId: testVault.id,
        text: text,
        vector: vector,
      );

      final chunks = await repository.getChunks(testVault.id);
      expect(chunks, hasLength(1));
      expect(chunks.first.text, equals(text));
      expect(chunks.first.vector, equals(vector));
      expect(chunks.first.vaultId, equals(testVault.id));
    });

    test('should get all chunks for vault', () async {
      await repository.addChunk(
        vaultId: testVault.id,
        text: 'chunk 1',
        vector: vec([1.0, 2.0]),
      );
      await repository.addChunk(
        vaultId: testVault.id,
        text: 'chunk 2',
        vector: vec([3.0, 4.0]),
      );

      final chunks = await repository.getChunks(testVault.id);
      expect(chunks, hasLength(2));
      expect(chunks.map((c) => c.text), containsAll(['chunk 1', 'chunk 2']));
    });

    test('should get chunk hashes for vault', () async {
      await repository.addChunk(
        vaultId: testVault.id,
        text: 'test chunk',
        vector: vec([1.0, 2.0]),
      );

      final hashes = await repository.getChunkHashes(testVault.id);
      expect(hashes, hasLength(1));
      expect(hashes.first, isA<String>());
      expect(hashes.first.length, equals(64)); // SHA-256 hash length
    });

    test('should delete chunk by hash', () async {
      const text = 'test chunk';
      await repository.addChunk(
        vaultId: testVault.id,
        text: text,
        vector: vec([1.0, 2.0]),
      );

      final hashes = await repository.getChunkHashes(testVault.id);
      final hash = hashes.first;

      await repository.deleteChunk(hash, testVault.id);

      final remainingHashes = await repository.getChunkHashes(testVault.id);
      expect(remainingHashes, isEmpty);
    });
  });

  group('Utility Functions', () {
    test('should calculate cosine similarity correctly', () {
      final vec1 = vec([1.0, 0.0, 0.0]);
      final vec2 = vec([1.0, 0.0, 0.0]);
      final vec3 = vec([0.0, 1.0, 0.0]);

      expect(Agent.cosineSimilarity(vec1, vec2), equals(1.0));
      expect(Agent.cosineSimilarity(vec1, vec3), equals(0.0));
    });

    test('should throw error for mismatched vector lengths', () {
      final vec1 = vec([1.0, 2.0]);
      final vec2 = vec([1.0, 2.0, 3.0]);

      expect(
        () => Agent.cosineSimilarity(vec1, vec2),
        throwsA(isA<AssertionError>()),
      );
    });

    test('should chunk text appropriately', () {
      // Short text should remain as single chunk
      const shortText = 'This is a short text.';
      final shortChunks = repository.chunkText(shortText);
      expect(shortChunks, hasLength(1));
      expect(shortChunks.first, equals(shortText));

      // Long text should be split into multiple chunks
      final longText = List.generate(
        5000,
        (i) => 'This is sentence number $i with more words to make it longer.',
      ).join(' ');
      final longChunks = repository.chunkText(longText);
      expect(longChunks.length, greaterThan(1));
    });

    test('should rank chunks by similarity', () {
      final chunks = [
        EmbeddingChunk(
          id: 1,
          vaultId: 1,
          hash: 'hash1',
          text: 'chunk1',
          vector: vec([1.0, 0.0, 0.0]),
        ),
        EmbeddingChunk(
          id: 2,
          vaultId: 1,
          hash: 'hash2',
          text: 'chunk2',
          vector: vec([0.8, 0.6, 0.0]),
        ),
        EmbeddingChunk(
          id: 3,
          vaultId: 1,
          hash: 'hash3',
          text: 'chunk3',
          vector: vec([0.0, 1.0, 0.0]),
        ),
      ];

      final queryVector = vec([1.0, 0.0, 0.0]);
      final ranked = repository.rankChunks(chunks, queryVector, 2);

      expect(ranked, hasLength(2));
      expect(ranked.first.text, equals('chunk1')); // Perfect match
      expect(ranked.last.text, equals('chunk2')); // Better than chunk3
    });
  });

  group('File System Operations', () {
    test('should walk directory and yield files', () async {
      // Create test file structure
      final testDir = Directory('${tempDir.path}/test_walk');
      await testDir.create();

      final testFile = File('${testDir.path}/test.md');
      await testFile.writeAsString('test content');

      final entities = repository.walkDirectory(testDir.path).toList();
      expect(entities, hasLength(1));
      expect(entities.first, isA<File>());
      expect(entities.first.path, equals(testFile.path));
    });

    test('should yield single file when path is file', () async {
      final testFile = File('${tempDir.path}/single.md');
      await testFile.writeAsString('test content');

      final entities = repository.walkDirectory(testFile.path).toList();
      expect(entities, hasLength(1));
      expect(entities.first.path, equals(testFile.path));
    });

    test('should detect stale vault', () async {
      final vault = await repository.createVault('test_vault', tempDir.path);

      // Create a markdown file
      final testFile = File('${tempDir.path}/test.md');
      await testFile.writeAsString('Initial content');

      // Vault should not be stale initially (no chunks in database)
      expect(await repository.isVaultStale(vault.id, vault.rootPath), isTrue);

      // Add chunk for the file content
      final chunks = repository.chunkText(await testFile.readAsString());
      for (final chunk in chunks) {
        await repository.addChunk(
          vaultId: vault.id,
          text: chunk,
          vector: vec(List.generate(10, (i) => Random().nextDouble())),
        );
      }

      // Now vault should not be stale
      expect(await repository.isVaultStale(vault.id, vault.rootPath), isFalse);

      // Modify file content
      await testFile.writeAsString('Modified content');

      // Vault should now be stale
      expect(await repository.isVaultStale(vault.id, vault.rootPath), isTrue);
    });
  });

  group('Sync Operations', () {
    test('should throw error when syncing non-existent vault', () async {
      expect(() => repository.syncVault('non-existent'), throwsArgumentError);
    });

    test('should detect file changes for sync operations', () async {
      // Create test vault and files
      final testDir = Directory('${tempDir.path}/sync_test');
      await testDir.create();

      final vault = await repository.createVault('sync-vault', testDir.path);

      // Create initial file
      final file1 = File('${testDir.path}/doc1.md');
      await file1.writeAsString('Initial content for document 1.');

      // Add a chunk manually to simulate existing data
      await repository.addChunk(
        vaultId: vault.id,
        text: 'Initial content for document 1.',
        vector: vec(List.generate(10, (i) => i.toDouble())),
      );

      // Check that vault is not stale with matching content
      expect(await repository.isVaultStale(vault.id, vault.rootPath), isFalse);

      // Modify file content
      await file1.writeAsString('Modified content for document 1.');

      // Check that vault is now stale
      expect(await repository.isVaultStale(vault.id, vault.rootPath), isTrue);

      // Add another file
      final file2 = File('${testDir.path}/doc2.md');
      await file2.writeAsString('Additional content for document 2.');

      // Vault should still be stale
      expect(await repository.isVaultStale(vault.id, vault.rootPath), isTrue);
    });
  });

  group('Vault Info Operations', () {
    test('should get vault info with file listings', () async {
      // Create test vaults with files
      final testDir1 = Directory('${tempDir.path}/vault1');
      final testDir2 = Directory('${tempDir.path}/vault2');
      await testDir1.create();
      await testDir2.create();

      await repository.createVault('vault1', testDir1.path);
      await repository.createVault('vault2', testDir2.path);

      // Create some markdown files
      await File('${testDir1.path}/doc1.md').writeAsString('Content 1');
      await File('${testDir1.path}/doc2.md').writeAsString('Content 2');
      await File('${testDir2.path}/readme.md').writeAsString('Readme content');

      // Create a non-markdown file that should be ignored
      await File('${testDir1.path}/notes.txt').writeAsString('Text file');

      final vaultInfos = await repository.getVaultInfo();

      expect(vaultInfos, hasLength(2));

      final vault1Info = vaultInfos.firstWhere((v) => v.vault.name == 'vault1');
      final vault2Info = vaultInfos.firstWhere((v) => v.vault.name == 'vault2');

      expect(vault1Info.markdownFiles, hasLength(2));
      expect(vault1Info.markdownFiles, containsAll(['doc1.md', 'doc2.md']));

      expect(vault2Info.markdownFiles, hasLength(1));
      expect(vault2Info.markdownFiles, contains('readme.md'));
    });

    test('should filter vault info by name', () async {
      final testDir = Directory('${tempDir.path}/filtered_vault');
      await testDir.create();

      await repository.createVault('test-vault', testDir.path);
      await repository.createVault('other-vault', testDir.path);

      await File('${testDir.path}/test.md').writeAsString('Test content');

      final filteredInfos = await repository.getVaultInfo('test-vault');

      expect(filteredInfos, hasLength(1));
      expect(filteredInfos.first.vault.name, equals('test-vault'));
      expect(filteredInfos.first.markdownFiles, contains('test.md'));
    });

    test('should return empty list for non-existent vault filter', () async {
      final vaultInfos = await repository.getVaultInfo('non-existent');
      expect(vaultInfos, isEmpty);
    });

    test('should handle vault with no markdown files', () async {
      final emptyDir = Directory('${tempDir.path}/empty_vault');
      await emptyDir.create();

      await repository.createVault('empty-vault', emptyDir.path);

      // Create a non-markdown file
      await File('${emptyDir.path}/readme.txt').writeAsString('Text file');

      final vaultInfos = await repository.getVaultInfo('empty-vault');

      expect(vaultInfos, hasLength(1));
      expect(vaultInfos.first.markdownFiles, isEmpty);
    });
  });

  group('Data Models', () {
    test('should serialize and deserialize Vault correctly', () {
      const vault = Vault(id: 1, name: 'test', rootPath: '/path');
      final map = vault.toMap();
      final deserialized = Vault.fromMap(map);

      expect(deserialized.id, equals(vault.id));
      expect(deserialized.name, equals(vault.name));
      expect(deserialized.rootPath, equals(vault.rootPath));
    });

    test('should serialize and deserialize Chunk correctly', () {
      final chunk = EmbeddingChunk(
        id: 1,
        vaultId: 2,
        hash: 'test_hash',
        text: 'test text',
        vector: vec([1.0, 2.0, 3.0]),
      );
      final map = chunk.toMap();
      final deserialized = EmbeddingChunk.fromMap(map);

      expect(deserialized.id, equals(chunk.id));
      expect(deserialized.vaultId, equals(chunk.vaultId));
      expect(deserialized.hash, equals(chunk.hash));
      expect(deserialized.text, equals(chunk.text));
      expect(deserialized.vector, equals(chunk.vector));
    });

    test('should create VaultInfo correctly', () {
      const vault = Vault(id: 1, name: 'test', rootPath: '/path');
      const markdownFiles = ['doc1.md', 'doc2.md'];

      const vaultInfo = VaultInfo(vault: vault, markdownFiles: markdownFiles);

      expect(vaultInfo.vault, equals(vault));
      expect(vaultInfo.markdownFiles, equals(markdownFiles));
    });
  });
}
