# Ragamuffin

A Dart package for Retrieval-Augmented Generation (RAG) that provides local
embedding storage with multi-provider AI integration via [the dartantic_ai
package](https://pub.dev/packages/dartantic_ai), designed for efficient document
querying with minimal cloud costs.

## Features

- 🔒 **Local Storage**: Stores embeddings in SQLite, only re-embedding on changes
- 🎯 **Smart Retrieval**: Support for targeted retrieval through cosine similarity ranking
- 🚀 **Cross-Platform**: Pure Dart implementation runs on macOS, Windows, and Linux

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

## Example CLI Tool

The repository includes a sample CLI application in the `example/` directory
that demonstrates the library's capabilities.

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
  - Examples: `openai`, `gemini:gemini-2.5-flash`

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

The CLI tool demonstrates practical usage patterns and can serve as a reference
implementation for your own applications.

## Environment Setup

Set the appropriate API key for your chosen provider:

```bash
export OPENAI_API_KEY=your_api_key_here
```

## Contributing

Issues and pull requests welcome! This library follows standard Dart conventions
and includes comprehensive tests.

## License

MIT License - see LICENSE file for details.
