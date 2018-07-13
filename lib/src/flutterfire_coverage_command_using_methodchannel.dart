// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'common.dart';

// TODO(jackson): Maybe scrape out of flutter/plugins
const Map<String, String> packages = const <String, String>{
//  'firebase_admob': 'googlemobileads',
//  'firebase_analytics': 'firebaseanalytics',
//  'firebase_auth': 'firebaseauth',
//  'firebase_core': 'firebasecore',
  'firebase_database': 'firebasedatabase',
  'cloud_firestore': 'firebasefirestore',
//  'firebase_messaging': 'firebasemessaging',
//  'firebase_storage': 'firebasestorage',
};

class FlutterFireCoverageCommand extends PluginCommand {
  FlutterFireCoverageCommand(Directory packagesDir) : super(packagesDir);

  @override
  final String name = 'flutterfire_coverage';

  @override
  final String description =
      'Analyzes the implementation status of FlutterFire using tests';

  @override
  Future<Null> run() async {
    for (String package in packages.keys) {
      await _analyzePackage(package, packages[package]);
    }
  }

  Future<Null> _analyzePackage(String package, String library) async {
    final Map<String, List<String>> iosMethods = await _getMethods(package, "m");
    final Map<String, List<String>> androidMethods = await _getMethods(package, "java");

    // Download the class names from Firebase docs
    // TODO(jackson): We might want to cache this list
    final String docs = 'https://firebase.google.com/docs/reference/swift/${library}/api/reference/Classes';
    html.Document document = html.parse((await http.get(docs)).body);
    for (html.Node classToken in document.getElementsByClassName('token')) {
      String className = classToken.text;
      print("===== $className =====");
      List<String> swiftMethods = <String>[];
      // Download the method names from Firebase docs
      final String classDocs = 'https://firebase.google.com/docs/reference/swift/${library}/api/reference/Classes/$className';
      html.Document document = html.parse((await http.get(classDocs)).body);
      for (html.Node methodToken in document.getElementsByClassName('token')) {
        swiftMethods.add(methodToken.text);
      }
      print("iOS\t${iosMethods[className]?.join("\t")}");
      print("Android\t${androidMethods[className]?.join("\t")}");
      print("Swift\t${swiftMethods?.join("\t")}");
    }
    print('');
  }

  // Used to parse iOS and Java files for classes and method names
  final RegExp _methodRegex = new RegExp('(\\w+)#(\\w+)', multiLine: true);

  Future<Map<String, List<String>>> _getMethods(String package, String extension) async {
    final Directory packageDir = new Directory("${packagesDir.path}/$package");
    final List<File> files = packageDir.listSync(recursive: true).where(
            (FileSystemEntity entity) => entity is File &&
                p.basename(entity.path).endsWith("Plugin.$extension")
    );
    assert(files.length == 1);
    String content = await files.first.readAsString();
    final Map<String, List<String>> methods = {};
    List<Match> matches = _methodRegex.allMatches(content);
    for (Match match in matches) {
      methods[match.group(1)] ??= [];
      methods[match.group(1)].add(match.group(2));
    }
    return methods;
  }
}
