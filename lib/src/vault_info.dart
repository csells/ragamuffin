import 'vault.dart';

/// Information about a vault including its metadata and file listings
class VaultInfo {
  /// Creates vault information with the given vault and file list.
  const VaultInfo({
    required this.vault,
    required this.markdownFiles,
  });

  /// The vault metadata.
  final Vault vault;
  
  /// List of relative paths to markdown files in the vault.
  final List<String> markdownFiles;
}
