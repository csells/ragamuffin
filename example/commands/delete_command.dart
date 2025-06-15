// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:io';

import 'package:args/command_runner.dart';

import '../globals.dart';

class DeleteCommand extends Command<void> {
  DeleteCommand() {
    argParser.addFlag('yes', abbr: 'y', help: 'Skip confirmation prompt');
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete a vault and all its chunks';

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('Usage: delete <name>');
    }

    final name = argResults!.rest[0];
    final force = argResults!['yes'] as bool;
    await _deleteVault(name, force: force);
  }

  Future<void> _deleteVault(String name, {required bool force}) async {
    final vault = await repository.getVault(name);
    if (vault == null) {
      stderr.writeln('No vault named "$name".');
      exit(1);
    }

    if (!force) {
      stdout.write(
        '⚠️  This will permanently delete vault "$name" and all its chunks.\n'
        'Continue? (y/N) ',
      );
      final ans = stdin.readLineSync()?.trim().toLowerCase();
      if (ans != 'y' && ans != 'yes') {
        print('Aborted.');
        exit(0);
      }
    }

    await repository.deleteVault(name);
    print('Vault "$name" deleted.');
  }
}
