// ignore_for_file: avoid_print, avoid_dynamic_calls

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:ragamuffin/ragamuffin.dart';

import '../globals.dart';

class ChatCommand extends Command<void> {
  @override
  String get name => 'chat';

  @override
  String get description => 'Start an interactive chat session with a vault';

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('Usage: chat <name>');
    }

    final name = argResults!.rest[0];
    await _chatLoop(name);
  }

  Future<void> _chatLoop(String name) async {
    final vault = await repository.getVault(name);
    if (vault == null) {
      stderr.writeln('No vault named "$name".');
      exit(1);
    }

    if (await repository.isVaultStale(vault.id, vault.rootPath)) {
      print(
        '\x1B[33m⚠️  Vault "$name" may be out-of-date. '
        'Run: dart run ragamuffin.dart --update $name\x1B[0m',
      );
    }

    final chunks = await repository.getChunks(vault.id);

    // Initialize the chat agent with tools
    final chatAgent = ChatAgent(repository, chunks);
    var history = <Message>[];

    void showHelp() {
      print('\n💬  Available commands:');
      print('    /help   - Show this help message');
      print('    /exit   - End the chat session');
      print('    /quit   - End the chat session');
      print('    /debug  - Toggle debug logging');
    }

    print('\n💬  Chat started. Type /help for available commands.');
    showHelp();

    while (true) {
      stdout.write('\n> ');
      final q = stdin.readLineSync()?.trim();
      if (q == null) continue;

      if (q.startsWith('/')) {
        final cmd = q.toLowerCase();
        switch (cmd) {
          case '/exit':
          case '/quit':
            print('\n👋  Goodbye!');
            return;
          case '/help':
            showHelp();
            continue;
          default:
            print('\n❌  Unknown command: $cmd');
            print('    Type /help for available commands');
            continue;
        }
      }

      // Let dartantic_ai handle everything automatically
      logger.fine('Sending query to agent: $q');
      final response = await chatAgent.run(q, messages: history);
      print('\n🤖  ${response.output}');

      // dartantic_ai automatically manages conversation state
      history = response.messages;
    }
  }
}
