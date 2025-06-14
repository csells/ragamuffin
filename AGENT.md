# Ragamuffin Agent Guide

## Project Structure
- **Main entry point**: `example/main.dart` - CLI RAG tool for querying
  documents with dartantic_ai
- **Library**: `lib/` - Contains core library code (minimal, most logic in
  example/)
- **Database**: SQLite (`ragamuffin.db`) - stores document embeddings and chunks
- **Subproject**: `packages/hnsw_dart/` - HNSW index implementation

## Commands
- **Run CLI**: `dart run example/main.dart [command]`
- **Format**: `dart format .`
- **Analyze**: `dart analyze`
- **Test**: `dart test` (no tests currently exist)

## Code Style (from analysis_options.yaml)
- Single quotes preferred over double quotes
- Use `final` liberally, avoid `always_specify_types`
- Relative imports for local files, package imports for external
- No trailing commas for single-line code
- Public API docs required for library code
- Ignore files: `**/*.g.dart`, `**/*.freezed.dart`

## Dart programming language preferences
- Prefer for-expressions over map(...).toList().
- Prefer switch expressions over switch statements.
- Use `const` constructors where possible.
- Use `late` for non-nullable fields initialized later.
- Use `??=` for default values.
- Use `??` for null-aware defaults.
- Format code to stay within 80 characters per line.

## Key Dependencies
- `dartantic_ai` - AI agent framework for embeddings and chat with tools
- `sqlite3` - Local vector storage
- `crypto` - Content hashing
- `args` - CLI argument parsing

## MCP preferences
- use dart-mcp-server when running tests and looking up package info, including links
  to package documentation and the associated github repo
- use deepwiki for github repo questions
