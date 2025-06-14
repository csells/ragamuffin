import 'dart:convert';
import 'dart:typed_data';

/// Represents a text chunk with its embedding vector
class EmbeddingChunk {
  /// Creates a new embedding chunk with the given properties.
  const EmbeddingChunk({
    required this.id,
    required this.vaultId,
    required this.hash,
    required this.text,
    required this.vector,
  });

  /// Creates a chunk from a map representation retrieved from database storage.
  factory EmbeddingChunk.fromMap(Map<String, dynamic> map) => EmbeddingChunk(
    id: map['id'] as int,
    vaultId: map['vault_id'] as int,
    hash: map['hash'] as String,
    text: map['text'] as String,
    vector: Float64List.fromList(
      (jsonDecode(map['vec'] as String) as List)
          .cast<num>()
          .map((n) => n.toDouble())
          .toList(),
    ),
  );

  /// The unique identifier for this chunk.
  final int id;

  /// The ID of the vault this chunk belongs to.
  final int vaultId;

  /// The SHA-256 hash of the text content for deduplication.
  final String hash;

  /// The text content of this chunk.
  final String text;

  /// The embedding vector representing this chunk's semantic meaning.
  final Float64List vector;

  /// Converts this chunk to a map representation suitable for database storage.
  Map<String, dynamic> toMap() => {
    'id': id,
    'vault_id': vaultId,
    'hash': hash,
    'text': text,
    'vec': jsonEncode(vector),
  };
}
