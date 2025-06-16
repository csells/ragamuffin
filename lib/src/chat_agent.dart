import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';

import 'embedding_chunk.dart';
import 'embedding_repository.dart';

Logger? _loggerInstance;
Logger get _logger => _loggerInstance ??= Logger('ragamuffin');

/// A typed chat agent for interacting with ragamuffin vaults.
class ChatAgent {
  /// Creates a new ChatAgent with the given repository and model string.
  ChatAgent(this._repository, this._model, List<EmbeddingChunk> chunks) {
    _initialize(chunks);
  }

  final String _model;
  late final Agent _agentWithTools;
  final EmbeddingRepository _repository;

  /// Initialize the agent with chunks from a vault.
  void _initialize(List<EmbeddingChunk> chunks) {
    final retrieveTool = Tool(
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
        _logger.info('tool(retrieve_chunks): $query');
        final vecQ = await _repository.createEmbedding(query);
        final hits = _repository
            .rankChunks(chunks, vecQ, 4)
            .map((c) => c.text)
            .join('\n---\n');
        return {'snippets': hits};
      },
    );

    _agentWithTools = Agent(
      _model,
      systemPrompt: '''
You are a helpful assistant that answers questions based ONLY on the content in Chris's vault. 
When asked a question:
1. First, use retrieve_chunks to search for relevant information in the vault
2. Then, answer the question using ONLY the information found in the vault
3. If the vault doesn't contain relevant information, say so clearly
4. Do not make up or infer information not present in the vault
5. Do not use any external knowledge unless it's explicitly mentioned in the vault''',
      tools: [retrieveTool],
    );
  }

  /// Run a query through the agent.
  Future<AgentResponse> run(String query, {List<Message>? messages}) =>
      _agentWithTools.run(query, messages: messages ?? []);
}
