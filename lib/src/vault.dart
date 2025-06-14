/// Represents a vault containing documents
class Vault {
  /// Creates a new vault with the given [id], [name], and [rootPath].
  const Vault({required this.id, required this.name, required this.rootPath});

  /// Creates a vault from a map representation retrieved from database storage.
  factory Vault.fromMap(Map<String, dynamic> map) => Vault(
    id: map['id'] as int,
    name: map['name'] as String,
    rootPath: map['root_path'] as String,
  );

  /// The unique identifier for this vault.
  final int id;

  /// The human-readable name of this vault.
  final String name;

  /// The file system path to the root directory containing the vault's
  /// documents.
  final String rootPath;

  /// Converts this vault to a map representation suitable for database storage.
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'root_path': rootPath,
  };
}
