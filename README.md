# Ragamuffin

A portable, developer-friendly RAG (Retrieval-Augmented Generation) tool for interrogating personal text files with LLM assistance, while minimizing cloud costs.

## Features

- 🔒 **Local Storage**: Stores embeddings in SQLite, only re-embedding on changes
- 🎯 **Smart Retrieval**: LLM performs targeted retrieval through OpenAI function calls
- 🚀 **Cross-Platform**: Runs identically on macOS, Windows, and Linux
- 📝 **Scriptable**: Command-line interface with no server or browser UI required
- ⚡ **Efficient**: Only incurs cloud costs for embedding and inference

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/ragamuffin.git
cd ragamuffin

# Run directly with Dart
dart run ragamuffin.dart [command]
```

## Usage

### Create a Vault

```bash
dart run ragamuffin.dart --create my-vault ~/Notes --yes
```

This will:
- Create a new vault named "my-vault"
- Scan the specified directory for markdown files
- Embed all text chunks
- Store vectors and text locally

### Update a Vault

```bash
dart run ragamuffin.dart --update my-vault
```

This will:
- Add new chunks
- Re-embed changed chunks
- Delete vanished chunks
- Print delta counts

### Chat with Your Vault

```bash
dart run ragamuffin.dart --chat my-vault
```

This will:
- Check for any changes in the vault
- Warn if the vault is stale
- Enter a REPL where you can chat with GPT-4
- The LLM will automatically retrieve relevant chunks as needed

### List Vaults

```bash
# List all vaults
dart run ragamuffin.dart --list

# List specific vault details
dart run ragamuffin.dart --list my-vault
```

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
- Uses GPT-4 with function-calling capabilities
- Memory footprint < 300 MB during cosine search
- Cold "create" for a 5 MB vault completes in under two minutes

## Future Plans

- Switchable embedding provider (Gemini compatibility)
- ANN index (HNSW) for larger chunk counts
- PDF chunker with text-position citations
- Optional local LLM via llama_cpp for offline answers

## License

[Your chosen license]

## Contributing

[Your contribution guidelines]
