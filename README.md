# Ragamuffin

A Dart library for Retrieval-Augmented Generation (RAG) that provides local embedding storage with multi-provider AI integration (OpenAI, Gemini, etc.), designed for efficient document querying with minimal cloud costs.

## Features

- 🔒 **Local Storage**: Stores embeddings in SQLite, only re-embedding on changes
- 🎯 **Smart Retrieval**: Support for targeted retrieval through cosine similarity ranking
- 🚀 **Cross-Platform**: Pure Dart implementation runs on macOS, Windows, and Linux
- ⚡ **Efficient**: Only incurs cloud costs for embedding and inference
- 🧪 **Well-Tested**: Comprehensive test suite with 29 passing tests
- 📚 **Clean API**: Repository pattern with typed database operations

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  ragamuffin:
    git: https://github.com/csells/ragamuffin.git
```

Then run:
```bash
dart pub get
```

## Usage

### Basic Setup

```dart
import 'package:ragamuffin/ragamuffin.dart';
import 'package:dartantic_ai/dartantic_ai.dart';

// Initialize repository with AI agent
final agent = Agent('gemini'); // or 'openai', 'gemini:gemini-2.5-flash', etc.
final repository = EmbeddingRepository('my_app.db', agent);
repository.initialize();

// Set up environment
// Ensure appropriate API key is set (GEMINI_API_KEY, OPENAI_API_KEY, etc.)
```

### Creating and Managing Vaults

```dart
// Create a vault
final vault = await repository.createVault('my-vault', '/path/to/docs');

// Check if vault exists
final exists = await repository.vaultExists('my-vault');

// Get vault by name
final vault = await repository.getVault('my-vault');

// List all vaults
final vaults = await repository.getAllVaults();

// Delete a vault
await repository.deleteVault('my-vault');
```

### Working with Embeddings and Chunks

```dart
// Generate embedding for text
final embedding = await repository.createEmbedding('Your text content');

// Add chunk with embedding
await repository.addChunk(
  vaultId: vault.id,
  text: 'Your text content',
  vector: embedding,
);

// Get all chunks for a vault
final chunks = await repository.getChunks(vault.id);

// Rank chunks by similarity to query
final queryVector = await repository.createEmbedding('search query');
final rankedChunks = repository.rankChunks(chunks, queryVector, 5);
```

### Vault Synchronization

```dart
// Sync vault with file system (add/update/remove chunks)
final result = await repository.syncVault('my-vault');
print('Added: ${result['added']}, Updated: ${result['updated']}, Deleted: ${result['deleted']}');

// Check if vault is stale (files changed on disk)
final isStale = await repository.isVaultStale(vault.id, vault.rootPath);
```

### Chat Integration

```dart
// Initialize chat agent with chunks
final chunks = await repository.getChunks(vault.id);
final chatAgent = ChatAgent(repository, chunks);

// The ChatAgent provides retrieval functionality for LLM conversations
// and can be integrated with dartantic_ai messaging systems
```

## API Reference

### EmbeddingRepository

Core repository class for managing vaults, chunks, and embeddings.

**Key Methods:**
- `initialize()` - Initialize database and create tables
- `createVault(name, rootPath)` - Create new vault
- `getVault(name)` - Retrieve vault by name
- `addChunk({vaultId, text, vector})` - Add text chunk with embedding
- `getChunks(vaultId)` - Get all chunks for vault
- `createEmbedding(text)` - Generate OpenAI embedding
- `rankChunks(chunks, queryVector, topK)` - Rank by cosine similarity
- `syncVault(name)` - Sync vault with file system
- `isVaultStale(vaultId, rootPath)` - Check if files changed

### Data Models

- **Vault**: Represents a collection of documents with `id`, `name`, and `rootPath`
- **EmbeddingChunk**: Text chunk with embedding vector, includes `id`, `vaultId`, `hash`, `text`, and `vector` 
- **VaultInfo**: Extended vault information including file lists

### ChatAgent

Provides retrieval functionality for chat interactions with access to document chunks.

## Technical Details

- Multi-provider AI support via dartantic_ai (OpenAI, Gemini, etc.)
- Default: Gemini embeddings, configurable via `--model` flag
- SQLite database with `vaults` and `chunks` tables
- Text chunking with ~6000 token limit per chunk
- Cosine similarity ranking for retrieval
- Memory footprint < 300 MB during cosine search
- Built with pure Dart (no FFI, no external binaries)

## Example CLI Tool

The repository includes a sample CLI application in the `example/` directory that demonstrates the library's capabilities.

### Running the Example

```bash
git clone https://github.com/csells/ragamuffin.git
cd ragamuffin
dart run example/main.dart [command]
```

### Available Commands

- **create** `<name> <path> [--yes]` - Create a new vault from files in a directory
- **update** `<name>` - Sync vault with file system changes  
- **chat** `<name>` - Start interactive chat session with vault
- **list** `[name]` - List vaults and their contents
- **delete** `<name> [--yes]` - Delete vault and all chunks

### Global Options

- `-m, --model` - Specify AI provider and model (defaults to "gemini")
  - Examples: `openai`, `gemini:gemini-2.5-flash`, `anthropic:claude-3-haiku`

### Example CLI Usage

```bash
# Create vault from directory (using default Gemini)
dart run example/main.dart create my-notes ~/Documents/Notes --yes

# Create vault using OpenAI
dart run example/main.dart --model openai create my-notes ~/Documents/Notes --yes

# Update vault after file changes
dart run example/main.dart update my-notes

# Chat with your documents
dart run example/main.dart chat my-notes

# List all vaults
dart run example/main.dart list

# Get help
dart run example/main.dart --help
```

The CLI tool demonstrates practical usage patterns and can serve as a reference implementation for your own applications.

## Environment Setup

Set the appropriate API key for your chosen provider:

```bash
export OPENAI_API_KEY=your_api_key_here
```

## Privacy & Security

- You'll be warned when text will be sent to your chosen AI provider for embedding
- Only embeddings and plain text are stored locally  
- No API keys are stored in the database
- Delete the database file to wipe all vectors

## Requirements

- Dart SDK 3.0+
- API key for your chosen provider (Gemini, OpenAI, Anthropic, etc.)
- SQLite3 (included via sqlite3 package)

## Contributing

Issues and pull requests welcome! This library follows standard Dart conventions and includes comprehensive tests.

## License

MIT License - see LICENSE file for details.
