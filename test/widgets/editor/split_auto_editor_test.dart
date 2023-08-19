import 'dart:math';

import 'package:file/memory.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/auto/pathplanner_auto.dart';
import 'package:pathplanner/util/pose2d.dart';
import 'package:pathplanner/commands/command_groups.dart';
import 'package:pathplanner/commands/path_command.dart';
import 'package:pathplanner/path/event_marker.dart';
import 'package:pathplanner/path/pathplanner_path.dart';
import 'package:pathplanner/path/rotation_target.dart';
import 'package:pathplanner/util/path_painter_util.dart';
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/widgets/editor/path_painter.dart';
import 'package:pathplanner/widgets/editor/split_auto_editor.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/auto_tree.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/commands/path_command_widget.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undo/undo.dart';

void main() {
  late PathPlannerAuto auto;
  late PathPlannerPath testPath;
  late SharedPreferences prefs;
  late ChangeStack undoStack;
  late bool autoChanged;

  setUp(() async {
    var fs = MemoryFileSystem();
    auto = PathPlannerAuto(
      name: 'test',
      sequence: SequentialCommandGroup(
        commands: [
          PathCommand(pathName: 'testPath'),
        ],
      ),
      autoDir: '/autos',
      fs: fs,
      startingPose: Pose2d(
        position: const Point(2.0, 2.0),
        rotation: 0.0,
      ),
      folder: null,
    );
    testPath = PathPlannerPath.defaultPath(
      name: 'testPath',
      pathDir: '/paths',
      fs: fs,
    );
    testPath.rotationTargets = [
      RotationTarget(waypointRelativePos: 0.5, rotationDegrees: 45),
    ];
    testPath.eventMarkers = [
      EventMarker(
        waypointRelativePos: 1.5,
        command: SequentialCommandGroup(commands: []),
      ),
    ];
    undoStack = ChangeStack();
    SharedPreferences.setMockInitialValues({
      PrefsKeys.holonomicMode: true,
      PrefsKeys.treeOnRight: true,
      PrefsKeys.robotWidth: 1.0,
      PrefsKeys.robotLength: 1.0,
    });
    prefs = await SharedPreferences.getInstance();
    autoChanged = false;
  });

  testWidgets('has painter and tree', (widgetTester) async {
    await widgetTester.binding.setSurfaceSize(const Size(1280, 720));

    await widgetTester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SplitAutoEditor(
          prefs: prefs,
          auto: auto,
          autoPaths: [testPath],
          allPathNames: const ['testPath', 'otherPath'],
          fieldImage: FieldImage.defaultField,
          undoStack: undoStack,
          onAutoChanged: () => autoChanged = true,
        ),
      ),
    ));

    var painters = find.byType(CustomPaint);
    bool foundPathPainter = false;
    for (var p in widgetTester.widgetList(painters)) {
      if ((p as CustomPaint).painter is PathPainter) {
        foundPathPainter = true;
      }
    }
    expect(foundPathPainter, true);
    expect(find.byType(AutoTree), findsOneWidget);
  });

  testWidgets('drag starting pose', (widgetTester) async {
    await widgetTester.binding.setSurfaceSize(const Size(1280, 720));

    await widgetTester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SplitAutoEditor(
          prefs: prefs,
          auto: auto,
          autoPaths: [testPath],
          allPathNames: const ['testPath', 'otherPath'],
          fieldImage: FieldImage.defaultField,
          undoStack: undoStack,
          onAutoChanged: () => autoChanged = true,
        ),
      ),
    ));

    var dragLocation = PathPainterUtil.pointToPixelOffset(
            auto.startingPose!.position,
            PathPainter.scale,
            FieldImage.defaultField) +
        const Offset(48, 48) + // Add 48 for padding
        const Offset(-2.0, 23.0); // Some weird buffer going on
    var oneMeterPixels = PathPainterUtil.metersToPixels(
        1.0, PathPainter.scale, FieldImage.defaultField);

    var posGesture = await widgetTester.startGesture(dragLocation,
        kind: PointerDeviceKind.mouse);
    addTearDown(posGesture.removePointer);

    await widgetTester.pump();

    for (int i = 0; i < oneMeterPixels; i++) {
      await posGesture.moveBy(const Offset(1, 1));
      await widgetTester.pump();
    }

    await posGesture.up();
    await widgetTester.pump();

    expect(autoChanged, true);
    expect(auto.startingPose!.position.x, closeTo(3.0, 0.1));
    expect(auto.startingPose!.position.y, closeTo(1.0, 0.1));

    undoStack.undo();
    expect(auto.startingPose!.position.x, closeTo(2.0, 0.1));
    expect(auto.startingPose!.position.y, closeTo(2.0, 0.1));
    autoChanged = false;

    var rotGesture = await widgetTester.startGesture(
        dragLocation +
            Offset(oneMeterPixels / 2, 0) +
            const Offset(4,
                4), // WHY DOES IT NEED THIS EXTRA BUFFER?!?!? FLUTTER TEST BAD
        kind: PointerDeviceKind.mouse);
    addTearDown(rotGesture.removePointer);

    await widgetTester.pump();

    for (int i = 0; i <= (oneMeterPixels / 2.0).ceil(); i++) {
      await rotGesture.moveBy(const Offset(-1, -2));
      await widgetTester.pump();
    }

    await rotGesture.up();
    await widgetTester.pump();

    expect(autoChanged, true);
    expect(auto.startingPose!.rotation, closeTo(90.0, 1.0));

    undoStack.undo();
    expect(auto.startingPose!.rotation, closeTo(0.0, 1.0));
  });

  testWidgets('path hover', (widgetTester) async {
    await widgetTester.binding.setSurfaceSize(const Size(1280, 720));

    await widgetTester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SplitAutoEditor(
          prefs: prefs,
          auto: auto,
          autoPaths: [testPath],
          allPathNames: const ['testPath', 'otherPath'],
          fieldImage: FieldImage.defaultField,
          undoStack: undoStack,
          onAutoChanged: () => autoChanged = true,
        ),
      ),
    ));

    final gesture =
        await widgetTester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    expect(find.byType(PathCommandWidget), findsOneWidget);

    await gesture
        .moveTo(widgetTester.getCenter(find.byType(PathCommandWidget)));
    await widgetTester.pump();

    await gesture.moveTo(Offset.infinite);
    await widgetTester.pump();
  });

  testWidgets('swap tree side', (widgetTester) async {
    await widgetTester.binding.setSurfaceSize(const Size(1280, 720));

    await widgetTester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SplitAutoEditor(
          prefs: prefs,
          auto: auto,
          autoPaths: [testPath],
          allPathNames: const ['testPath', 'otherPath'],
          fieldImage: FieldImage.defaultField,
          undoStack: undoStack,
          onAutoChanged: () => autoChanged = true,
        ),
      ),
    ));

    final swapButton = find.byTooltip('Move to Other Side');

    expect(swapButton, findsOneWidget);

    await widgetTester.tap(swapButton);
    await widgetTester.pump();

    expect(prefs.getBool(PrefsKeys.treeOnRight), false);

    await widgetTester.tap(swapButton);
    await widgetTester.pump();

    expect(prefs.getBool(PrefsKeys.treeOnRight), true);
  });

  testWidgets('change tree size', (widgetTester) async {
    await widgetTester.binding.setSurfaceSize(const Size(1280, 720));

    await widgetTester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SplitAutoEditor(
          prefs: prefs,
          auto: auto,
          autoPaths: [testPath],
          allPathNames: const ['testPath', 'otherPath'],
          fieldImage: FieldImage.defaultField,
          undoStack: undoStack,
          onAutoChanged: () => autoChanged = true,
        ),
      ),
    ));

    await widgetTester.dragFrom(
        widgetTester.getCenter(find.byType(SplitAutoEditor)),
        const Offset(-200, 0));

    await widgetTester.pump(const Duration(seconds: 1));

    expect(prefs.getDouble(PrefsKeys.editorTreeWeight), closeTo(0.65, 0.01));

    await widgetTester.tap(find.byTooltip('Move to Other Side'));
    await widgetTester.pump();

    await widgetTester.dragFrom(
        widgetTester.getCenter(find.byType(SplitAutoEditor)) +
            const Offset(200, 0),
        const Offset(-200, 0));

    await widgetTester.pump(const Duration(seconds: 1));

    expect(prefs.getDouble(PrefsKeys.editorTreeWeight), closeTo(0.5, 0.01));
  });
}