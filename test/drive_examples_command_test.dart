import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:flutter_plugin_tools/src/drive_examples_command.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  group('$DriveExamplesCommand', () {
    CommandRunner runner;
    RecordingProcessRunner processRunner;

    setUp(() {
      initializeFakePackages();
      processRunner = RecordingProcessRunner();
      final DriveExamplesCommand command = DriveExamplesCommand(
          mockPackagesDir, mockFileSystem,
          processRunner: processRunner);

      runner = CommandRunner<Null>(
          'drive_examples_command', 'Test for $DriveExamplesCommand');
      runner.addCommand(command);
    });

    test('runs driver tests', () async {
      createFakePlugin('plugin', withSingleExample: true,
          withExtraFiles: <List<String>>[
        <String>['example', 'test_driver', 'plugin_e2e.dart'],
        <String>['example', 'test_driver', 'plugin_e2e_test.dart'],
      ]);

      List<String> output = await runCapturingPrint(runner, <String>[
        'drive-examples',
      ]);


      expect(
        output,
        orderedEquals(<String>[
          '\RUNNING DRIVER TEST for plugin/test_driver/plugin_e2e.dart',
          '\n\n',
          'All driver tests successful!',
        ]),
      );

      expect(
        processRunner.recordedCalls,
        orderedEquals(<ProcessCall>[
          ProcessCall(
            'flutter',
            'drive test_driver/plugin_e2e.dart'.split(' '),
            null),
        ]),
      );

      cleanupPackages();
    });
  });
}
