import 'dart:convert';
import 'dart:io';

// Compiled by Windows CI to exercise the real process boundary without changing
// an installed app. Real package replacement is checked by packaging smoke tests.
Future<void> main(List<String> arguments) async {
  final directory = arguments.singleWhere((argument) => argument.startsWith('/DIR=')).substring(5);
  await File('$directory/arguments.json').writeAsString(jsonEncode(arguments));
  exit(int.parse(await File('$directory/exit-code').readAsString()));
}
