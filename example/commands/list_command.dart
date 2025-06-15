// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:io';

import 'package:args/command_runner.dart';

import '../globals.dart';

class ListCommand extends Command<void> {
  @override
  String get name => 'list';

  @override
  String get description => 'List vaults or show details for a specific vault';

  @override
  Future<void> run() async {
    final filter = argResults!.rest.isNotEmpty ? argResults!.rest[0] : null;
    await _listVaults(filter);
  }

  Future<void> _listVaults(String? filter) async {
    final vaultInfos = await repository.getVaultInfo(filter);

    if (vaultInfos.isEmpty) {
      stderr.writeln(
        filter == null ? 'No vaults.' : 'No vault named "$filter".',
      );
      return;
    }

    for (final info in vaultInfos) {
      print('\n🗄️  ${info.vault.name}  →  ${info.vault.rootPath}');
      if (info.markdownFiles.isEmpty) {
        print('   (no *.md)');
      } else {
        for (final file in info.markdownFiles) {
          print('   • $file');
        }
      }
    }
  }
}
