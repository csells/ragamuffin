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
git clone https://github.com/csells/ragamuffin.git
cd ragamuffin

# Run directly with Dart
dart run example/main.dart [command]
```

## Usage

### Create a File-Set

```bash
dart run example/main.dart create my-files ~/Notes --yes
```

This will:
- Create a new file-set named "my-files"
- Scan the specified directory for markdown files
- Embed all text chunks
- Store vectors and text locally

### Update a File-Set

```bash
dart run example/main.dart update my-files
```

This will:
- Add new chunks
- Re-embed changed chunks
- Delete vanished chunks
- Print delta counts

### Chat with Your File-Set

```bash
dart run example/main.dart chat my-files
```

This will:
- Check for any changes in the file-set
- Warn if the file-set is stale
- Enter a REPL where you can chat with GPT-4
- The LLM will automatically retrieve relevant chunks as needed

### List File-Sets

```bash
# List all file-sets
dart run example/main.dart list

# List specific file-set details
dart run example/main.dart list my-files
```

### Delete a File-Set

```bash
dart run example/main.dart delete my-files --yes
```

This will:
- Delete the file-set and all its chunks from the database
- Prompt for confirmation unless --yes is provided

## Environment Setup

Set your OpenAI API key:

```bash
export OPENAI_API_KEY=your_api_key_here
```

## Privacy & Security

- You'll be warned once per file-set that text will be sent to OpenAI
- Only embeddings and plain text are stored locally
- No API keys are stored in the database
- Delete `ragamuffin.db` to wipe all vectors

## Technical Details

- Uses OpenAI's text-embedding-3-small (1536-dim) for embeddings
- Uses GPT-4o-mini with function-calling capabilities
- Memory footprint < 300 MB during cosine search
- Cold "create" for a 5 MB file-set completes in under two minutes

## Future Plans

- Switchable embedding provider (Gemini compatibility)
- ANN index (HNSW) for larger chunk counts
- PDF chunker with text-position citations
- Image embeddings using image descriptions
- Optional local LLM via llama_cpp for offline answers
