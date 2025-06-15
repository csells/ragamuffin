// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:io';

import 'package:args/command_runner.dart';

import '../globals.dart';

class CreateCommand extends Command<void> {
  CreateCommand() {
    argParser.addFlag('yes', abbr: 'y', help: 'Skip confirmation prompt');
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a new vault from files in a directory';

  @override
  Future<void> run() async {
    if (argResults!.rest.length < 2) {
      usageException('Usage: create <name> <file|dir>');
    }

    final name = argResults!.rest[0];
    final root = argResults!.rest[1];
    final force = argResults!['yes'] as bool;

    await _createVault(name, root, force: force);
  }

  Future<void> _createVault(
    String name,
    String root, {
    required bool force,
  }) async {
    if (!force) {
      stdout.write(
        '⚠️  Your files will be sent to OpenAI to generate embeddings.\n'
        'Continue? (y/N) ',
      );
      final ans = stdin.readLineSync()?.trim().toLowerCase();
      if (ans != 'y' && ans != 'yes') {
        print('Aborted.');
        exit(0);
      }
    }

    try {
      final vault = await repository.createVault(name, root);
      final result = await repository.syncVault(vault.name);
      print('Vault "$name" created → added: ${result['added']} chunks');
    } on Exception catch (ex) {
      stderr.writeln('Error: Vault "$name": $ex');
      exit(1);
    }
  }
}
