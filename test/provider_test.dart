import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:ragamuffin/ragamuffin.dart';
import 'package:test/test.dart';

void main() {
  group('Provider Tests', () {
    late String testDbPath;

    setUp(() {
      testDbPath = 'test_ragamuffin.db';
    });

    tearDown(() {
      final file = File(testDbPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    test('EmbeddingRepository works with OpenAI agent', () async {
      if (Platform.environment['OPENAI_API_KEY'] == null) {
        markTestSkipped('OPENAI_API_KEY environment variable not set');
        return;
      }

      final agent = Agent('openai');
      final repository = EmbeddingRepository(testDbPath, agent);
      repository.initialize();

      // Test embedding creation
      final embedding = await repository.createEmbedding('test text');
      expect(embedding.length, greaterThan(0));

      repository.close();
    });

    test('EmbeddingRepository works with Gemini agent', () async {
      if (Platform.environment['GEMINI_API_KEY'] == null) {
        markTestSkipped('GEMINI_API_KEY environment variable not set');
        return;
      }

      final agent = Agent('gemini');
      final repository = EmbeddingRepository(testDbPath, agent);
      repository.initialize();

      // Test embedding creation
      final embedding = await repository.createEmbedding('test text');
      expect(embedding.length, greaterThan(0));

      repository.close();
    });

    test('ChatAgent works with OpenAI provider', () async {
      if (Platform.environment['OPENAI_API_KEY'] == null) {
        markTestSkipped('OPENAI_API_KEY environment variable not set');
        return;
      }

      final agent = Agent('openai:gpt-4o-mini');
      final repository = EmbeddingRepository(testDbPath, agent);
      repository.initialize();

      // Create a test vault
      final vault = await repository.createVault('test', '.');

      // Add some test chunks
      const testText = 'This is a test document about cats and dogs.';
      final vector = await repository.createEmbedding(testText);
      await repository.addChunk(
        vaultId: vault.id,
        text: testText,
        vector: vector,
      );

      final chunks = await repository.getChunks(vault.id);
      final chatAgent = ChatAgent(repository, 'openai:gpt-4o-mini', chunks);

      // Test chat functionality
      final response = await chatAgent.run('What animals are mentioned?');
      expect(response.output, isNotEmpty);

      repository.close();
    });

    test('ChatAgent works with Gemini provider', () async {
      if (Platform.environment['GEMINI_API_KEY'] == null) {
        markTestSkipped('GEMINI_API_KEY environment variable not set');
        return;
      }

      final agent = Agent('gemini');
      final repository = EmbeddingRepository(testDbPath, agent);
      repository.initialize();

      // Create a test vault
      final vault = await repository.createVault('test', '.');

      // Add some test chunks
      const testText = 'This is a test document about space exploration.';
      final vector = await repository.createEmbedding(testText);
      await repository.addChunk(
        vaultId: vault.id,
        text: testText,
        vector: vector,
      );

      final chunks = await repository.getChunks(vault.id);
      final chatAgent = ChatAgent(
        repository,
        'gemini:gemini-1.5-flash',
        chunks,
      );

      // Test chat functionality
      final response = await chatAgent.run('What topic is discussed?');
      expect(response.output, isNotEmpty);

      repository.close();
    });
  });
}
