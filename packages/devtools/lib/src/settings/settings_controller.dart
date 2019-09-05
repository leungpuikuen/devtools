// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';

import '../globals.dart';
import '../service_registrations.dart' as registrations;
import '../version.dart';

// TODO(kenzie): we should listen for flag value updates and update the settings
// screen with the new flag values. See
// https://github.com/flutter/devtools/issues/988.

typedef OnFlutterVersionChanged = void Function(FlutterVersion version);

typedef OnFlagListChanged = void Function(FlagList flagList);

class SettingsController {
  SettingsController({
    @required this.onFlutterVersionChanged,
    @required this.onFlagListChanged,
  });

  final OnFlutterVersionChanged onFlutterVersionChanged;

  final OnFlagListChanged onFlagListChanged;

  final flutterVersionServiceAvailable = Completer();

  Future<void> entering() async {
    onFlagListChanged(await serviceManager.service.getFlagList());
    await _onFlutterVersionChanged();
  }

  Future<void> _onFlutterVersionChanged() async {
    if (await serviceManager.connectedApp.isAnyFlutterApp) {
      serviceManager.hasRegisteredService(
        registrations.flutterVersion.service,
        (bool serviceAvailable) async {
          if (serviceAvailable && !flutterVersionServiceAvailable.isCompleted) {
            flutterVersionServiceAvailable.complete();
            final FlutterVersion version = FlutterVersion.parse(
                (await serviceManager.getFlutterVersion()).json);
            onFlutterVersionChanged(version);
          } else {
            onFlutterVersionChanged(null);
          }
        },
      );
    } else {
      onFlutterVersionChanged(null);
    }
  }
}