// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Error thrown when a command needs to exit with a non-zero exit code.
class ToolExit extends Error {
  ToolExit(this.exitCode);

  final int exitCode;
}

abstract class PluginCommand extends Command<Null> {
  static const String _pluginsArg = 'plugins';
  static const String _shardIndexArg = 'shardIndex';
  static const String _shardCountArg = 'shardCount';
  final Directory packagesDir;
  int _shardIndex;
  int _shardCount;

  PluginCommand(this.packagesDir) {
    argParser.addMultiOption(
      _pluginsArg,
      splitCommas: true,
      help:
          'Specifies which plugins the command should run on (before sharding).',
      valueHelp: 'plugin1,plugin2,...',
    );
    argParser.addOption(
      _shardIndexArg,
      help: 'Specifies the zero-based index of the shard to '
          'which the command applies.',
      valueHelp: 'i',
      defaultsTo: '0',
    );
    argParser.addOption(
      _shardCountArg,
      help: 'Specifies the number of shards into which plugins are divided.',
      valueHelp: 'n',
      defaultsTo: '1',
    );
  }

  int get shardIndex {
    if (_shardIndex == null) {
      checkSharding();
    }
    return _shardIndex;
  }

  int get shardCount {
    if (_shardCount == null) {
      checkSharding();
    }
    return _shardCount;
  }

  void checkSharding() {
    final int shardIndex = int.tryParse(argResults[_shardIndexArg]);
    final int shardCount = int.tryParse(argResults[_shardCountArg]);
    if (shardIndex == null) {
      usageException('$_shardIndexArg must be an integer');
    }
    if (shardCount == null) {
      usageException('$_shardCountArg must be an integer');
    }
    if (shardCount < 1) {
      usageException('$_shardCountArg must be positive');
    }
    if (shardIndex < 0 || shardCount <= shardIndex) {
      usageException(
          '$_shardIndexArg must be in the half-open range [0..$shardCount[');
    }
    _shardIndex = shardIndex;
    _shardCount = shardCount;
  }

  /// Returns the root Dart package folders of the plugins involved in this
  /// command execution.
  Stream<Directory> getPlugins() async* {
    // To avoid assuming consistency of `Directory.list` across command
    // invocations, we collect and sort the plugin folders before sharding.
    // This is considered an implementation detail which is why the API still
    // uses streams.
    final List<Directory> allPlugins = await _getAllPlugins().toList();
    allPlugins.sort((Directory d1, Directory d2) => d1.path.compareTo(d2.path));
    // Sharding 10 elements into 3 shards should yield shard sizes 4, 4, 2.
    // Sharding  9 elements into 3 shards should yield shard sizes 3, 3, 3.
    // Sharding  2 elements into 3 shards should yield shard sizes 1, 1, 0.
    final int shardSize = allPlugins.length ~/ shardCount +
        (allPlugins.length % shardCount == 0 ? 0 : 1);
    final int start = min(shardIndex * shardSize, allPlugins.length);
    final int end = min(start + shardSize, allPlugins.length);
    for (Directory plugin in allPlugins.sublist(start, end)) {
      yield plugin;
    }
  }

  /// Returns the root Dart package folders of the plugins involved in this
  /// command execution, assuming there is only one shard.
  Stream<Directory> _getAllPlugins() {
    final Set<String> packages = new Set<String>.from(argResults[_pluginsArg]);
    return packagesDir
        .list(followLinks: false)
        .where(_isDartPackage)
        .where((FileSystemEntity entity) =>
            packages.isEmpty || packages.contains(p.basename(entity.path)))
        .cast<Directory>();
  }

  /// Returns the example Dart package folders of the plugins involved in this
  /// command execution.
  Stream<Directory> getExamples() => getPlugins().expand(_getExamplesForPlugin);

  /// Returns all Dart package folders (typically, plugin + example) of the
  /// plugins involved in this command execution.
  Stream<Directory> getPackages() async* {
    await for (Directory plugin in getPlugins()) {
      yield plugin;
      yield* plugin
          .list(recursive: true, followLinks: false)
          .where(_isDartPackage)
          .cast<Directory>();
    }
  }

  /// Returns the files contained, recursively, within the plugins
  /// involved in this command execution.
  Stream<File> getFiles() {
    return getPlugins().asyncExpand<File>((Directory folder) => folder
        .list(recursive: true, followLinks: false)
        .where((FileSystemEntity entity) => entity is File)
        .cast<File>());
  }

  /// Returns whether the specified entity is a directory containing a
  /// `pubspec.yaml` file.
  bool _isDartPackage(FileSystemEntity entity) {
    return entity is Directory &&
        new File(p.join(entity.path, 'pubspec.yaml')).existsSync();
  }

  /// Returns the example Dart packages contained in the specified plugin, or
  /// an empty List, if the plugin has no examples.
  List<Directory> _getExamplesForPlugin(Directory plugin) {
    final Directory exampleFolder =
        new Directory(p.join(plugin.path, 'example'));
    if (!exampleFolder.existsSync()) {
      return <Directory>[];
    }
    if (_isDartPackage(exampleFolder)) {
      return <Directory>[exampleFolder];
    }
    // Only look at the subdirectories of the example directory if the example
    // directory itself is not a Dart package, and only look one level below the
    // example directory for other dart packages.
    return exampleFolder.listSync().where(_isDartPackage);
  }
}

Future<int> runAndStream(String executable, List<String> args,
    {Directory workingDir, bool exitOnError: false}) async {
  final Process process =
      await Process.start(executable, args, workingDirectory: workingDir?.path);
  stdout.addStream(process.stdout);
  stderr.addStream(process.stderr);
  if (exitOnError && await process.exitCode != 0) {
    final String error =
        _getErrorString(executable, args, workingDir: workingDir);
    print('$error See above for details.');
    throw new ToolExit(await process.exitCode);
  }
  return process.exitCode;
}

Future<ProcessResult> runAndExitOnError(String executable, List<String> args,
    {Directory workingDir, bool exitOnError: false}) async {
  final ProcessResult result =
      await Process.run(executable, args, workingDirectory: workingDir?.path);
  if (result.exitCode != 0) {
    final String error =
        _getErrorString(executable, args, workingDir: workingDir);
    print('$error Stderr:\n${result.stdout}');
    throw new ToolExit(result.exitCode);
  }
  return result;
}

String _getErrorString(String executable, List<String> args,
    {Directory workingDir}) {
  final String workdir = workingDir == null ? '' : ' in ${workingDir.path}';
  return 'ERROR: Unable to execute "$executable ${args.join(' ')}"$workdir.';
}
