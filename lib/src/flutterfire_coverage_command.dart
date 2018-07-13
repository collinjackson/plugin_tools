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

const List<_API> apis = const <_API>[
  const _API(flutterName: 'firebase_admob', swiftName: 'googlemobileads'),
  const _API(
    flutterName: 'firebase_analytics',
    swiftName: 'firebaseanalytics',

  ),
  const _API(flutterName: 'firebase_auth', swiftName: 'firebaseauth'),
  const _API(flutterName: 'firebase_core', swiftName: 'firebasecore'),
  const _API(flutterName: 'firebase_database', swiftName: 'firebasedatabase'),
  const _API(flutterName: 'cloud_firestore', swiftName: 'firebasefirestore'),
  const _API(flutterName: 'firebase_messaging', swiftName: 'firebasemessaging'),
  const _API(flutterName: 'firebase_storage', swiftName: 'firebasestorage'),
  const _API(flutterName: 'firebase_remote_config', swiftName: 'firebaseremoteconfig'),
  const _API(flutterName: 'firebase_performance', swiftName: 'firebaseperformance'),
  const _API(flutterName: 'firebase_dynamic_links', swiftName: 'firebasedynamiclinks'),
];

class _Method {
  _Method({ this.parent, this.name });
  final _Class parent;
  final String name;

  Future<bool> isImplementedInFlutter() async {
    final String classDocs = 'https://www.dartdocs.org/documentation/'
        '${parent.api.flutterName}/latest/${parent.api.flutterName}'
        '/${parent.name}/$name.html';
    if ((await http.get(classDocs)).statusCode == 200) {
      print("Found $classDocs");
      return true;
    } else {
      print("Missing $classDocs");
      return false;
    }
  }
}

class _Class {
  _Class({ this.api, this.name, this.methods });
  final _API api;
  final String name;
  final List<_Method> methods;
}

class _API {
  const _API({ this.flutterName, this.swiftName });
  final String flutterName;
  final String swiftName;

  Future<List<_Class>> scrapeSwift() async {
    final RegExp _methodRegex = new RegExp('^\w*');
    final List<_Class> results = <_Class>[];
    final String docs = 'https://firebase.google.com/docs/reference/swift/${swiftName}/api/reference/Classes';
    html.Document document = html.parse((await http.get(docs)).body);
    for (html.Node classToken in document.getElementsByClassName('token')) {
      List<_Method> methods = <_Method>[];
      final Map<String, bool> seenMethods = <String, bool>{};
      final String className = classToken.text;
      final _Class clazz = new _Class(
        api: this,
        name: className,
        methods: methods,
      );
      // Download the method names from Firebase docs
      final String classDocs = 'https://firebase.google.com/docs/reference/swift/${swiftName}/api/reference/Classes/$className';
      final html.Document document = html.parse((await http.get(classDocs)).body);
      for (html.Node methodToken in document.getElementsByClassName('token')) {
        final String shortName = _methodRegex.firstMatch(methodToken.text).group(0);
        print('shortName $shortName');
        if (!seenMethods.containsKey(shortName)) {
          methods.add(new _Method(name: shortName, parent: clazz));
          seenMethods[shortName] = true;
        }
      }
      results.add(clazz);
    }
    return results;
  }

  Future<List<_Class>> scrapeDart() async {
    final RegExp _versionRegex = new RegExp('([^/]*)/index.html');
    final List<_Class> results = <_Class>[];
    final String latestUrl = 'https://www.dartdocs.org/documentation/'
        '$flutterName/latest';
    http.Response response = await http.get(latestUrl);
    String version = _versionRegex.firstMatch(response.body).group(1);
    final String docs = 'https://www.dartdocs.org/documentation/'
    '$flutterName/$version/$flutterName/$flutterName-library.html';
    html.Document document = html.parse((await http.get(docs)).body);
    for (html.Node classToken in document.getElementsByClassName('name')) {
      final List<_Method> dartMethods = <_Method>[];
      final String className = classToken.text;
      final _Class clazz = new _Class(
        api: this,
        name: className,
        methods: dartMethods,
      );
      // Download the method names from Firebase docs
      final String classDocs = 'https://www.dartdocs.org/documentation/'
          '${flutterName}/$version/${flutterName}/${className}-class.html';
      final html.Document document = html.parse((await http.get(classDocs)).body);
      for (html.Node methodToken in document.getElementsByClassName('name')) {
        dartMethods.add(new _Method(name: methodToken.text, parent: clazz));
      }
      results.add(clazz);
    }
    return results;
  }

}

class FlutterFireCoverageCommand extends PluginCommand {
  FlutterFireCoverageCommand(Directory packagesDir) : super(packagesDir);

  @override
  final String name = 'flutterfire_coverage';

  @override
  final String description =
      'Analyzes the implementation status of FlutterFire';

  @override
  Future<Null> run() async {
    for (_API api in apis) {
      final List<_Class> classes = await api.scrapeSwift();
      for (_Class clazz in classes) {
        for (_Method method in clazz.methods) {
          print('${api.swiftName}\t${clazz.name}\t${method.name}');
        }
      }
    }
  }
}
