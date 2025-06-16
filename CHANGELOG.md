## 0.2.0

### 🔧 Fixes
- Fixed CLI help functionality - now properly displays usage information with `--help`, `-h`, or when run without parameters
- No longer requires API key to view help information

### ✨ Enhancements  
- Added multi-provider AI support via dartantic_ai integration
- Default model changed from OpenAI to Gemini (gemini:gemini-2.5-flash)
- Support for custom model specification via `--model` flag (e.g., `openai`, `gemini:gemini-2.5-flash`)

### 🔄 Breaking Changes
- Environment variable changed from `OPENAI_API_KEY` to provider-specific keys (e.g., `GEMINI_API_KEY` for default)
- Library now requires dartantic_ai Agent initialization instead of direct OpenAI client

## 0.1.0

### 🎉 Initial Release

A feature-complete RAG (Retrieval-Augmented Generation) CLI tool with library support.

### ✨ Features

**Core Functionality:**
- Create, update, list, and delete document vaults
- Automatic text chunking with ~6000 token limit
- OpenAI embeddings (text-embedding-3-small) with local SQLite storage
- Smart retrieval via GPT-4o-mini with function calling
- Cross-platform support (macOS, Windows, Linux)

**CLI Commands:**
- `create <name> <path> [--yes]` - Create new vault with consent prompts
- `update <name>` - Sync vault with file system changes
- `chat <name>` - Interactive chat with vault content
- `list [name]` - Show vaults and file inventory
- `delete <name> [--yes]` - Remove vault and all chunks

**Developer Experience:**
- Pure Dart implementation (no FFI dependencies)
- Scriptable command-line interface
- Comprehensive test suite (22 tests covering all major functionality)
- Clean repository pattern for library usage
- Full API documentation

### 🏗️ Architecture

**Database Schema:**
- `vaults(id, name, root_path)` - Vault metadata
- `chunks(id, vault_id, hash, text, vec)` - Text chunks with embeddings

**Library Structure:**
- `EmbeddingRepository` - Core repository class
- `Vault` - Vault data model
- `EmbeddingChunk` - Text chunk with vector data
- Utility functions for text processing and similarity ranking

### 🔒 Privacy & Security

- Explicit consent prompts before sending data to OpenAI
- Local-only storage of embeddings and text
- No API keys stored in database
- Vault staleness detection with clear warnings

### 🧪 Testing

- Comprehensive test coverage for all repository operations
- Vault CRUD operations testing
- Text chunking and similarity ranking tests
- File system operations testing
- Data model serialization/deserialization tests
- Isolated test environment with temporary databases

### 📋 Requirements

- Dart SDK
- OpenAI API key (set via `OPENAI_API_KEY` environment variable)
- SQLite support (included with Dart)

### 🎯 Performance

- Memory footprint < 300 MB during cosine search
- Cold vault creation completes in under 2 minutes for 5MB of content
- Efficient incremental updates (only re-embed changed content)
- Brute-force cosine similarity search suitable for <10k chunks
