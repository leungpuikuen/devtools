// @dart=2.9

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import '../../devtools.dart' as devtools;
import '../config_specific/launch_url/launch_url.dart';
import '../config_specific/logger/logger.dart' as logger;
import '../config_specific/server/server.dart' as server;
import '../primitives/auto_dispose_mixin.dart';
import 'common_widgets.dart';
import 'theme.dart';
import 'utils.dart';
import 'version.dart';

class ReleaseNotesViewer extends StatefulWidget {
  const ReleaseNotesViewer({
    Key key,
    @required this.releaseNotesController,
    @required this.child,
  }) : super(key: key);

  final ReleaseNotesController releaseNotesController;

  final Widget child;

  @override
  _ReleaseNotesViewerState createState() => _ReleaseNotesViewerState();
}

class _ReleaseNotesViewerState extends State<ReleaseNotesViewer>
    with AutoDisposeMixin, SingleTickerProviderStateMixin {
  static const viewerWidth = 600.0;

  /// Animation controller for animating the opening and closing of the viewer.
  AnimationController visibilityController;

  /// A curved animation that matches [visibilityController].
  Animation<double> visibilityAnimation;

  String markdownData;

  bool isVisible;

  @override
  void initState() {
    super.initState();
    isVisible = widget.releaseNotesController.releaseNotesVisible.value;
    markdownData = widget.releaseNotesController.releaseNotesMarkdown.value;

    visibilityController = longAnimationController(this);
    // Add [densePadding] to the end to account for the space between the
    // release notes viewer and the right edge of DevTools.
    visibilityAnimation =
        Tween<double>(begin: 0, end: viewerWidth + densePadding)
            .animate(visibilityController);

    addAutoDisposeListener(widget.releaseNotesController.releaseNotesVisible,
        () {
      setState(() {
        isVisible = widget.releaseNotesController.releaseNotesVisible.value;
        if (isVisible) {
          visibilityController.forward();
        } else {
          visibilityController.reverse();
        }
      });
    });

    markdownData = widget.releaseNotesController.releaseNotesMarkdown.value;
    addAutoDisposeListener(widget.releaseNotesController.releaseNotesMarkdown,
        () {
      setState(() {
        markdownData = widget.releaseNotesController.releaseNotesMarkdown.value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          widget.child,
          ReleaseNotes(
            releaseNotesController: widget.releaseNotesController,
            visibilityAnimation: visibilityAnimation,
            markdownData: markdownData,
          ),
        ],
      ),
    );
  }
}

class ReleaseNotes extends AnimatedWidget {
  const ReleaseNotes({
    Key key,
    @required this.releaseNotesController,
    @required Animation<double> visibilityAnimation,
    @required this.markdownData,
  }) : super(key: key, listenable: visibilityAnimation);

  final ReleaseNotesController releaseNotesController;

  final String markdownData;

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    final theme = Theme.of(context);
    return Positioned(
      top: densePadding,
      bottom: densePadding,
      right: densePadding -
          (_ReleaseNotesViewerState.viewerWidth - animation.value),
      width: _ReleaseNotesViewerState.viewerWidth,
      child: Card(
        elevation: defaultElevation,
        color: theme.scaffoldBackgroundColor,
        clipBehavior: Clip.hardEdge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(defaultBorderRadius),
          side: BorderSide(
            color: theme.focusColor,
          ),
        ),
        child: Column(
          children: [
            AreaPaneHeader(
              title: const Text('What\'s new in DevTools?'),
              needsTopBorder: false,
              rightActions: [
                IconButton(
                  padding: const EdgeInsets.all(0.0),
                  onPressed: () =>
                      releaseNotesController.toggleReleaseNotesVisible(false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            markdownData == null
                ? const Text('Stay tuned for updates.')
                : Expanded(
                    child: Markdown(
                      data: markdownData,
                      onTapLink: (_, href, __) => launchUrl(href, context),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class ReleaseNotesController {
  ReleaseNotesController() {
    _init();
  }

  static const _unsupportedPathSyntax = '{{site.url}}';

  static const _flutterDocsSite = 'https://docs.flutter.dev';

  ValueListenable<String> get releaseNotesMarkdown => _releaseNotesMarkdown;

  final _releaseNotesMarkdown = ValueNotifier<String>(null);

  ValueListenable<bool> get releaseNotesVisible => _releaseNotesVisible;

  final _releaseNotesVisible = ValueNotifier<bool>(false);

  void _init() {
    if (server.isDevToolsServerAvailable && !isEmbedded()) {
      _maybeFetchReleaseNotes();
    }
  }

  void _maybeFetchReleaseNotes() async {
    final lastReleaseNotesShownVersion =
        await server.getLastShownReleaseNotesVersion();
    SemanticVersion previousVersion;
    if (lastReleaseNotesShownVersion.isEmpty) {
      previousVersion = SemanticVersion();
    } else {
      previousVersion = SemanticVersion.parse(lastReleaseNotesShownVersion);
    }
    // Parse the current version instead of using [devtools.version] directly to
    // strip off any build metadata (any characters following a '+' character).
    // Release notes will be hosted on the Flutter website with a version number
    // that does not contain any build metadata.
    final parsedCurrentVersion = SemanticVersion.parse(devtools.version);
    final parsedCurrentVersionStr = parsedCurrentVersion.toString();
    if (parsedCurrentVersion > previousVersion) {
      try {
        String releaseNotesMarkdown = await http.read(
          Uri.parse(_releaseNotesUrl(parsedCurrentVersionStr)),
        );
        // This is a workaround so that the images in release notes will appear.
        // The {{site.url}} syntax is best practices for the flutter website
        // repo, where these release notes are hosted, so we are performing this
        // workaround on our end to ensure the images render properly.
        releaseNotesMarkdown = releaseNotesMarkdown.replaceAll(
          _unsupportedPathSyntax,
          _flutterDocsSite,
        );

        _releaseNotesMarkdown.value = releaseNotesMarkdown;
        toggleReleaseNotesVisible(true);
        unawaited(
          server.setLastShownReleaseNotesVersion(parsedCurrentVersionStr),
        );
      } catch (e) {
        // Fail gracefully if we cannot find release notes for the current
        // version of DevTools.
        _releaseNotesMarkdown.value = null;
        toggleReleaseNotesVisible(false);
        logger.log(
          'Warning: could not find release notes for DevTools version '
          '$parsedCurrentVersionStr. $e',
          logger.LogLevel.warning,
        );
      }
    }
  }

  void toggleReleaseNotesVisible(bool visible) {
    _releaseNotesVisible.value = visible;
  }

  String _releaseNotesUrl(String currentVersion) {
    return 'https://docs.flutter.dev/development/tools/devtools/release-notes/release-notes-$currentVersion-src.md';
  }
}