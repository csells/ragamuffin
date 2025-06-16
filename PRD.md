# Product Requirements Document
Project codename: Ragamuffin

## Purpose and background

Chris wants a portable, developer-friendly way to interrogate personal text
files (for example an Obsidian vault) with large-language-model help, while
incurring cloud costs only for embedding and inference.  Ragamuffin is a
single-file Dart console tool that:
- stores embeddings locally in SQLite, so re-embedding happens only on change
- lets the LLM perform its own targeted retrieval through an OpenAI function
  call, avoiding the "embed the whole query" inefficiency of naïve RAG
- runs exactly the same on macOS, Windows and Linux, is scriptable, and needs no
  server or browser UI

The document formalises scope, behaviour and technical contracts.

⸻

## Goals
 - Create, update, list and chat against named "vaults" from the command line.
 - Never re-embed unchanged text; detect drift and warn the user in chat mode.
 - Expose a single tool (retrieve_chunks) to the LLM so it can pull only the
   snippets it decides it needs.
 - Require explicit consent before the first upload of any user content.
 - Keep every dependency pure Dart (no FFI, no binaries) for the MVP.

## User stories
1. As Chris I run dart run example/main.dart create my-vault ~/Notes --yes and
the tool embeds every markdown chunk in that directory, then returns to the
prompt.
2. As Chris I later run dart run example/main.dart chat my-vault, edit a file
	during the session, and Ragamuffin warns me the vault is stale.
3. As a shell script I can pipe update in a cron job without prompts.
4. As Chris I type "list" and see all vault names with their root paths and file
inventory.
5. As Chris I can delete a vault and all its chunks with delete <name>.

## Functional specification

### Commands	Behaviour
create <name> <path> [--yes]	Adds a row to vaults, scans <path> (file or
directory).  On first run asks: "⚠️ Files will be uploaded … Proceed?" unless
--yes present.  Each text chunk: SHA-256, embed via /v1/embeddings, store vector
and text.  Fails if name exists. update <name>	Looks up root_path.  Adds new
chunks, re-embeds changed chunks, deletes vanished chunks, prints delta counts.
chat <name>	Before chatting, recomputes SHA-256 of all disk chunks and compares
to hashes in SQLite.  If mismatch prints a yellow warning with the exact update
command.  Enters a REPL: each user line is sent to GPT-4o-mini with the
retrieve_chunks tool registered.  When the model calls the function, Ragamuffin
does an in-process cosine ranking of vectors, returns JSON snippets, then
streams the model's final answer. list [name]	Dumps vaults, their root paths and
relative Markdown file list. delete <name> [--yes]	Deletes the vault and all
its chunks from the database. On first run asks: "⚠️ This will permanently
delete vault ... Continue?" unless --yes present. Fails if vault doesn't exist.

### Data model (SQLite)

```sql
vaults(id, name UNIQUE, root_path)
chunks(id, vault_id FK, hash, text, vec JSON)
```

vec is a JSON-encoded List<double> (embedding). hash + vault_id is unique.

### Privacy and security
- Warn once per vault that text is sent to OpenAI.
- Store only embeddings and plain text locally; no keys in the DB.
- User can delete ragamuffin.db to wipe all vectors.

## Open issues / future
- Flutter GUI
- web deployment
- PDF/epub ingestion
- ANN indexing beyond brute-force cosine search
- image embeddings calculated using image descriptions.

