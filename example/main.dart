// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/chat_command.dart';
import 'commands/create_command.dart';
import 'commands/delete_command.dart';
import 'commands/list_command.dart';
import 'commands/update_command.dart';
import 'globals.dart';

Future<void> main(List<String> argv) async {
  final runner =
      CommandRunner<void>('ragamuffin', 'A CLI RAG tool for querying documents')
        ..addCommand(CreateCommand())
        ..addCommand(UpdateCommand())
        ..addCommand(ChatCommand())
        ..addCommand(ListCommand())
        ..addCommand(DeleteCommand());

  try {
    initializeLogging();
    await runner.run(argv);
  } on Exception catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  } finally {
    repository.close();
  }

  exit(0); // otherwise the async calls can cause the process to hang
}
