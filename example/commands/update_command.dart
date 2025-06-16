// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/command_runner.dart';

import '../globals.dart';

class UpdateCommand extends Command<void> {
  @override
  String get name => 'update';

  @override
  String get description => 'Update an existing vault with file changes';

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('Usage: update <name>');
    }

    final name = argResults!.rest[0];
    final model = globalResults!['model'] as String;
    initRepository(model);
    await _updateVault(name);
  }

  Future<void> _updateVault(String name) async {
    final vault = await repository.getVault(name);
    if (vault == null) {
      stderr.writeln('No vault named "$name". Run create command first.');
      exit(1);
    }

    final result = await repository.syncVault(vault.name);
    print(
      'Vault "$name" updated → '
      'added: ${result['added']}, deleted: ${result['deleted']}',
    );
  }
}
