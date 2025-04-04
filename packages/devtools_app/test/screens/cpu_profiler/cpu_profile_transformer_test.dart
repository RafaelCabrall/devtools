// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app/src/screens/profiler/cpu_profile_model.dart';
import 'package:devtools_app/src/screens/profiler/cpu_profile_transformer.dart';
import 'package:devtools_app/src/shared/utils/profiler_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_infra/test_data/cpu_profiler/cpu_profile.dart';

void main() {
  group('CpuProfileTransformer', () {
    late CpuProfileTransformer cpuProfileTransformer;
    late CpuProfileData cpuProfileData;

    setUp(() {
      cpuProfileTransformer = CpuProfileTransformer();
      cpuProfileData = CpuProfileData.fromJson(cpuProfileResponseJson);
    });

    test('processData', () async {
      expect(cpuProfileData.processed, isFalse);
      await cpuProfileTransformer.processData(
        cpuProfileData,
        processId: 'test',
      );
      expect(cpuProfileData.processed, isTrue);
      expect(
        cpuProfileData.cpuProfileRoot.profileAsString(),
        goldenCpuProfileString,
      );
    });

    test('process response with missing leaf frame', () {
      bool runTest() {
        final cpuProfileDataWithMissingLeaf = CpuProfileData.fromJson(
          responseWithMissingLeafFrame,
        );
        expect(() async {
          await cpuProfileTransformer.processData(
            cpuProfileDataWithMissingLeaf,
            processId: 'test',
          );
        }, throwsA(const TypeMatcher<AssertionError>()));
        return true;
      }

      // Only run this test if asserts are enabled.
      assert(runTest());
    });
  });

  group('BottomUpTransformer', () {
    late BottomUpTransformer<CpuStackFrame> transformer;

    setUp(() {
      transformer = BottomUpTransformer<CpuStackFrame>();
    });

    test('cascadeSampleCounts', () {
      void verifySampleCount(
        CpuStackFrame stackFrame, {
        required int targetExcl,
        required int targetIncl,
      }) {
        expect(stackFrame.exclusiveSampleCount, targetExcl);
        expect(stackFrame.inclusiveSampleCount, targetIncl);
        for (final child in stackFrame.children) {
          verifySampleCount(
            child,
            targetExcl: targetExcl,
            targetIncl: targetIncl,
          );
        }
      }

      final stackFrame = testStackFrame.deepCopy();
      transformer.cascadeSampleCounts(stackFrame);

      verifySampleCount(
        stackFrame,
        targetExcl: testStackFrame.exclusiveSampleCount,
        targetIncl: testStackFrame.inclusiveSampleCount,
      );
    });

    test('processData step by step', () async {
      expect(testStackFrame.profileAsString(), testStackFrameStringGolden);
      final bottomUpRoots = await transformer.generateBottomUpRoots(
        node: testStackFrame,
        parent: null,
        bottomUpRoots: [],
      );

      // Verify the original stack frame was not modified.
      expect(testStackFrame.profileAsString(), testStackFrameStringGolden);

      expect(bottomUpRoots.length, 6);

      // Set the bottom up sample counts for the roots.
      bottomUpRoots.forEach(transformer.cascadeSampleCounts);

      final buf = StringBuffer();
      for (final stackFrame in bottomUpRoots) {
        buf.writeln(stackFrame.profileAsString());
      }
      expect(buf.toString(), bottomUpPreMergeGolden);

      // Merge the bottom up roots.
      await mergeCpuProfileRoots(bottomUpRoots);

      expect(bottomUpRoots.length, 4);

      buf.clear();
      for (final stackFrame in bottomUpRoots) {
        buf.writeln(stackFrame.profileAsString());
      }
      expect(buf.toString(), bottomUpGolden);
    });

    test('processData step by step when skipping the root node', () async {
      final bottomUpRoots = await transformer.generateBottomUpRoots(
        node: testStackFrameWithRoot,
        parent: null,
        bottomUpRoots: [],
        skipRoot: true,
      );

      expect(bottomUpRoots.length, 6);

      // Set the bottom up sample counts for the roots.
      bottomUpRoots.forEach(transformer.cascadeSampleCounts);

      final buf = StringBuffer();
      for (final stackFrame in bottomUpRoots) {
        buf.writeln(stackFrame.profileAsString());
      }
      expect(buf.toString(), bottomUpPreMergeGolden);

      // Merge the bottom up roots.
      await mergeCpuProfileRoots(bottomUpRoots);

      expect(bottomUpRoots.length, 4);

      buf.clear();
      for (final stackFrame in bottomUpRoots) {
        buf.writeln(stackFrame.profileAsString());
      }
      expect(buf.toString(), bottomUpGolden);
    });

    test('bottomUpRootsFor', () async {
      expect(
        testStackFrameWithRoot.profileAsString(),
        testStackFrameWithRootStringGolden,
      );
      final bottomUpRoots = await transformer.bottomUpRootsFor(
        topDownRoot: testStackFrameWithRoot,
        mergeSamples: mergeCpuProfileRoots,
        rootedAtTags: false,
      );

      // Verify the original stack frame was not modified.
      expect(
        testStackFrameWithRoot.profileAsString(),
        testStackFrameWithRootStringGolden,
      );

      expect(bottomUpRoots.length, 4);

      final buf = StringBuffer();
      for (final stackFrame in bottomUpRoots) {
        buf.writeln(stackFrame.profileAsString());
      }
      expect(buf.toString(), bottomUpGolden);
    });

    test('bottomUpRootsFor rootedAtTags', () async {
      expect(
        testTagRootedStackFrame.profileAsString(),
        testTagRootedStackFrameStringGolden,
      );

      // Note: this needs to be rooted at a root frame before transforming as
      // a tree rooted at a root frame is what is provided in cpu_profile_model.dart.
      final bottomUpRoots = await transformer.bottomUpRootsFor(
        topDownRoot: CpuStackFrame.root(zeroProfileMetaData)
          ..addChild(testTagRootedStackFrame),
        mergeSamples: mergeCpuProfileRoots,
        rootedAtTags: true,
      );

      // Verify the original stack frame was not modified.
      expect(
        testTagRootedStackFrame.profileAsString(),
        testTagRootedStackFrameStringGolden,
      );

      expect(bottomUpRoots.length, equals(1));

      final buf = StringBuffer();
      for (final stackFrame in bottomUpRoots) {
        buf.writeln(stackFrame.profileAsString());
      }
      expect(buf.toString(), tagRootedBottomUpGolden);
    });
  });
}
