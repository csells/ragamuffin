// ignore_for_file: avoid_print

// TODO: turn with these techniques:
// https://blog.stackademic.com/this-custom-ai-reads-1-000s-of-pdfs-and-answers-like-a-human-heres-how-i-built-it-fce2132eabde

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

  runner.argParser.addOption(
    'model',
    abbr: 'm',
    defaultsTo: 'openai',
    help:
        'Provider and, optionally, model to use '
        '(e.g., openai, gemini:gemini-2.5-flash, etc.)',
  );

  try {
    initLogging();

    // Handle help and empty args before parsing
    if (argv.isEmpty || argv.contains('--help') || argv.contains('-h')) {
      runner.printUsage();
      return;
    }

    await runner.run(argv);
  } on UsageException catch (e) {
    stderr.writeln('${e.message}\n');
    runner.printUsage();
    exit(1);
  } on Exception catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  } finally {
    closeRepository();
  }

  exit(0); // otherwise the async calls can cause the process to hang
}
