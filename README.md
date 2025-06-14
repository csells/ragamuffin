# Ragamuffin

A portable, developer-friendly RAG (Retrieval-Augmented Generation) tool for interrogating personal text files with LLM assistance, while minimizing cloud costs.

## Features

- 🔒 **Local Storage**: Stores embeddings in SQLite, only re-embedding on changes
- 🎯 **Smart Retrieval**: LLM performs targeted retrieval through OpenAI function calls
- 🚀 **Cross-Platform**: Runs identically on macOS, Windows, and Linux
- 📝 **Scriptable**: Command-line interface with no server or browser UI required
- ⚡ **Efficient**: Only incurs cloud costs for embedding and inference
- 🧪 **Well-Tested**: Comprehensive test suite with 22 passing tests
- 📚 **Library**: Clean repository pattern for reusable embedding functionality

## Installation

```bash
# Clone the repository
git clone https://github.com/csells/ragamuffin.git
cd ragamuffin

# Run directly with Dart
dart run example/main.dart [command]
```

## Usage

### Create a Vault

```bash
dart run example/main.dart create my-vault ~/Notes --yes
```

This will:
- Create a new vault named "my-vault"
- Scan the specified directory for markdown files
- Embed all text chunks using OpenAI's text-embedding-3-small
- Store vectors and text locally in SQLite
- Ask for confirmation before sending data to OpenAI (unless `--yes` is provided)

### Update a Vault

```bash
dart run example/main.dart update my-vault
```

This will:
- Add new chunks for files that have been added
- Re-embed chunks for files that have changed
- Delete chunks for files that have been removed
- Print delta counts showing what was added/removed

### Chat with Your Vault

```bash
dart run example/main.dart chat my-vault
```

This will:
- Check for any changes in the vault files
- Warn if the vault is stale and suggest running update
- Enter a REPL where you can chat with GPT-4o-mini
- The LLM will automatically retrieve relevant chunks using the `retrieve_chunks` tool
- Type `/help` for available commands, `/exit` to quit, `/debug` to toggle logging

### List Vaults

```bash
# List all vaults
dart run example/main.dart list

# List specific vault details
dart run example/main.dart list my-vault
```

This will show:
- Vault names and root paths
- Relative paths of all markdown files in each vault

### Delete a Vault

```bash
dart run example/main.dart delete my-vault --yes
```

This will:
- Delete the vault and all its chunks from the database
- Prompt for confirmation unless `--yes` is provided
- Fail if the vault doesn't exist

## Environment Setup

Set your OpenAI API key:

```bash
export OPENAI_API_KEY=your_api_key_here
```

## Privacy & Security

- You'll be warned once per vault that text will be sent to OpenAI
- Only embeddings and plain text are stored locally
- No API keys are stored in the database
- Delete `ragamuffin.db` to wipe all vectors

## Technical Details

- Uses OpenAI's text-embedding-3-small (1536-dim) for embeddings
- Uses GPT-4o-mini with function-calling capabilities
- Memory footprint < 300 MB during cosine search
- Cold "create" for a 5 MB vault completes in under two minutes
- Built with pure Dart (no FFI, no external binaries)
- SQLite database with `vaults` and `chunks` tables
- Text chunking with ~6000 token limit per chunk
- Cosine similarity ranking for retrieval

## Library Usage

Ragamuffin can also be used as a library in your Dart projects:

```dart
import 'package:ragamuffin/ragamuffin.dart';

final repository = EmbeddingRepository('my_app.db');
repository.initialize();

// Create a vault
final vault = await repository.createVault('my-vault', '/path/to/docs');

// Add chunks with embeddings
await repository.addChunk(
  vaultId: vault.id,
  text: 'Your text content',
  vector: await repository.createEmbedding('Your text content'),
);

// Search and rank chunks
final chunks = await repository.getChunks(vault.id);
final queryVector = await repository.createEmbedding('search query');
final ranked = repository.rankChunks(chunks, queryVector, 5);
```

## Future Plans

- Switchable embedding provider (Gemini compatibility)
- ANN index (HNSW) for larger chunk counts
- PDF chunker with text-position citations
- Image embeddings using image descriptions
- Optional local LLM via llama_cpp for offline answers
