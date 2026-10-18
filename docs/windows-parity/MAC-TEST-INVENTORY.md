# Mac source test inventory

Reference source: `7925944`. Generated 2026-10-18. These are source cases to map to Windows, not Windows passes. Mac local baseline: 92 core tests and 262 disposable native checks; physical third-party behavior remains separately verified.

## Core test entry points

### [InteractionAndUpdateTests.swift](../../macos/Tests/BentoCoreTests/InteractionAndUpdateTests.swift)

- [ ] `testStatusHoldConsumesReleaseAndFiresOnce` — Windows equivalent/evidence: pending.
- [ ] `testNativeSeamReclaimsRoundedStripWithoutChangingMembership` — Windows equivalent/evidence: pending.
- [ ] `testDesktopWorkAreaReclaimsHiddenMenuAndDockWithoutUsingCameraArea` — Windows equivalent/evidence: pending.
- [ ] `testPhysicalEdgeMovesWholeSectionWhenLeafSwapCannotFit` — Windows equivalent/evidence: pending.
- [ ] `testSectionMovePreservesClampedWidthsAndSkipsAlreadyOutermostSection` — Windows equivalent/evidence: pending.
- [ ] `testSectionMovementCarriesSourceGroupAndDoesNotActivateOnAnotherDisplay` — Windows equivalent/evidence: pending.
- [ ] `testResumeRetainsDisplaySlotIdentityAndRatioWithoutAdmittingFloatingWindows` — Windows equivalent/evidence: pending.
- [ ] `testFloatingCenterDropInsertsWithoutDisplacingAndEmptyDisplayAcceptsDrop` — Windows equivalent/evidence: pending.
- [ ] `testImpossibleDropShowsConflictWithoutChangingWorkspace` — Windows equivalent/evidence: pending.
- [ ] `testSplitPreviewIsStableAcrossRepeatedSamplesInEveryDirection` — Windows equivalent/evidence: pending.
- [ ] `testSplitCacheInvalidatesForWorkAreaAndGapAndMemoizesConflict` — Windows equivalent/evidence: pending.
- [ ] `testMotionAcceleratesAndSettlesGentlyWithoutOvershoot` — Windows equivalent/evidence: pending.
- [ ] `testMotionEndpointsAndMonotonicity` — Windows equivalent/evidence: pending.
- [ ] `testDockReopenGetsSpaceBeforeExistingWindows` — Windows equivalent/evidence: pending.
- [ ] `testNativeDropQuickSwapAndTimedSplit` — Windows equivalent/evidence: pending.
- [ ] `testPreviewMatchesFinalSlotsAfterSourceRemovalAndMinimumClamping` — Windows equivalent/evidence: pending.
- [ ] `testHoldIndicatorResetsWhenPointerMovesToCenter` — Windows equivalent/evidence: pending.
- [ ] `testLeavingTargetResetsHoldAndOutsideDropCancels` — Windows equivalent/evidence: pending.
- [ ] `testInfeasibleTargetIsNotOffered` — Windows equivalent/evidence: pending.
- [ ] `testGripClampsAndDoesNotMutateSnapshot` — Windows equivalent/evidence: pending.
- [ ] `testOffCenterGripKeepsAnchorAcrossBothAxesAndOddGaps` — Windows equivalent/evidence: pending.
- [ ] `testNativeBorderChangesAncestorAndNeighbor` — Windows equivalent/evidence: pending.
- [ ] `testSignedOTAConfigurationRejectsUnsafeSources` — Windows equivalent/evidence: pending.
- [ ] `testOfficialSparkleArchiveSignatureAndCorruptionRejection` — Windows equivalent/evidence: pending.
- [ ] `testLiveToggleRestoresOnlyItsOwnKeyAndKeepsOriginalBaseline` — Windows equivalent/evidence: pending.
- [ ] `testLiveValueChangeKeepsFirstOriginalAndRespectsManualChange` — Windows equivalent/evidence: pending.
- [ ] `testLiveRefreshFailureKeepsRecoverableOriginalValues` — Windows equivalent/evidence: pending.
- [ ] `testInterruptedLiveValueChangeRestoresEitherOwnedValue` — Windows equivalent/evidence: pending.
- [ ] `testExactRestorationAndAbsentKeyDeletion` — Windows equivalent/evidence: pending.
- [ ] `testCrashRecoveryAndManualChoiceWins` — Windows equivalent/evidence: pending.
- [ ] `testPartialWriteFailureRollsBackAndRetainsRecoveryJournal` — Windows equivalent/evidence: pending.
- [ ] `testFailedRefreshCanRecoverNextLaunch` — Windows equivalent/evidence: pending.

### [LayoutTests.swift](../../macos/Tests/BentoCoreTests/LayoutTests.swift)

- [ ] `testRecentActivationPrimaryAndOldestOverflow` — Windows equivalent/evidence: pending.
- [ ] `testRecentActivationHonorsAsymmetricLimitsAndImpossibleApps` — Windows equivalent/evidence: pending.
- [ ] `testPairCapacityMatchesBothPossibleSplitAxes` — Windows equivalent/evidence: pending.
- [ ] `testNativeCellRoundingStaysInsideItsSlot` — Windows equivalent/evidence: pending.
- [ ] `testVisibleNonFocusedAppCanReflowExistingSlots` — Windows equivalent/evidence: pending.
- [ ] `testChatAndTerminalFitEitherOrientationAtExactLimits` — Windows equivalent/evidence: pending.
- [ ] `testLiveDockGeometryReplacesStaleReservation` — Windows equivalent/evidence: pending.
- [ ] `testActivationDoesNotHideFittingAppsToEnlargeThePrimary` — Windows equivalent/evidence: pending.
- [ ] `testOrderIndependentConstraintGrouping` — Windows equivalent/evidence: pending.
- [ ] `testRealBrowserAndChatLimitsKeepAllFourAppsUsable` — Windows equivalent/evidence: pending.
- [ ] `testSelectionKeepsMoreUsableAppsWithRecentUseAsTieBreaker` — Windows equivalent/evidence: pending.
- [ ] `testSelectionUsesRecencyWhenEqualCountsFit` — Windows equivalent/evidence: pending.
- [ ] `testEightAppCapacitySearchHasStableGeometry` — Windows equivalent/evidence: pending.
- [ ] `testSharedWindowsGeometryFixtures` — Windows equivalent/evidence: pending.
- [ ] `testAutomaticOneThroughTwelve` — Windows equivalent/evidence: pending.
- [ ] `testPortraitAndAsymmetricMinima` — Windows equivalent/evidence: pending.
- [ ] `testInvalidAndImpossibleInputs` — Windows equivalent/evidence: pending.
- [ ] `testFittingLeavesOversizedWindowsOut` — Windows equivalent/evidence: pending.
- [ ] `testFittingChoosesUsableSubsetWhenTogetherTooLarge` — Windows equivalent/evidence: pending.
- [ ] `testFittingPreservesEditsAndRefreshesLearnedMinimums` — Windows equivalent/evidence: pending.
- [ ] `testFocusedAppDoesNotCauseEvictionForAnIndividuallyImpossibleWindow` — Windows equivalent/evidence: pending.
- [ ] `testAdmissionReflowsFragmentedSlotsBeforeEvictingAnApp` — Windows equivalent/evidence: pending.
- [ ] `testDockAdmissionEvictsOldestAndOnlyAsManyAsNeeded` — Windows equivalent/evidence: pending.
- [ ] `testDockAdmissionPreservesEditedLayoutWhenAllFit` — Windows equivalent/evidence: pending.
- [ ] `testCrowdedDockAdmissionReplacesOneSlotWithoutMovingNeighbors` — Windows equivalent/evidence: pending.
- [ ] `testImpossibleDockWindowDoesNotEvictUsableWindows` — Windows equivalent/evidence: pending.
- [ ] `testFittingRejectsInvalidInputsRatherThanSkippingThem` — Windows equivalent/evidence: pending.
- [ ] `testFourDirectionsAndNoDuplicates` — Windows equivalent/evidence: pending.
- [ ] `testCrossDisplaySwapAndRemoval` — Windows equivalent/evidence: pending.
- [ ] `testSiblingPromotedAndInsertionPreservesRoot` — Windows equivalent/evidence: pending.
- [ ] `testUndoRedoBranchAndBound` — Windows equivalent/evidence: pending.
- [ ] `testHoldQuickDropCancellationAndJitter` — Windows equivalent/evidence: pending.
- [ ] `testZoneBoundsAndRoundTripPersistence` — Windows equivalent/evidence: pending.
- [ ] `testSeededThousandOperationExercise` — Windows equivalent/evidence: pending.

### [ResizeHandleTests.swift](../../macos/Tests/BentoCoreTests/ResizeHandleTests.swift)

- [ ] `testEquivalentHandlesNeverMoveWindowsAndHaveStableIdentity` — Windows equivalent/evidence: pending.
- [ ] `testBottomRowResizesHorizontallyWithoutMovingTopRow` — Windows equivalent/evidence: pending.
- [ ] `testCenterSelectsSharedRowAndSideSelectsLocalRow` — Windows equivalent/evidence: pending.
- [ ] `testLocalVerticalEditKeepsHorizontalResizeAvailable` — Windows equivalent/evidence: pending.
- [ ] `testColumnsHaveTheSameSharedAndLocalOptions` — Windows equivalent/evidence: pending.
- [ ] `testLocalGripPaddingAndUniversalRemainderOnBothAxes` — Windows equivalent/evidence: pending.
- [ ] `testJoinCandidatesOnlyIncludeSharedSections` — Windows equivalent/evidence: pending.
- [ ] `testJoiningOneSeamDoesNotCueAnUnrelatedExistingSeam` — Windows equivalent/evidence: pending.
- [ ] `testDockReflowKeepsJoinedRowsWhenOneBranchHitsMinimum` — Windows equivalent/evidence: pending.
- [ ] `testImpossibleSharedRowRetainsMembershipWithoutOverlap` — Windows equivalent/evidence: pending.
- [ ] `testMiddleRowCanResizeIndependentlyInThreeRowGrid` — Windows equivalent/evidence: pending.
- [ ] `testNoGripIsOfferedWhenNeitherNeighborCanResize` — Windows equivalent/evidence: pending.
- [ ] `testShownMenuCorrectsStaleExpandedGeometryOnItsOwnDisplay` — Windows equivalent/evidence: pending.
- [ ] `testNearbyRowsSnapAndRestorePerpendicularLocalHandles` — Windows equivalent/evidence: pending.
- [ ] `testNearbyColumnsSnapSymmetrically` — Windows equivalent/evidence: pending.
- [ ] `testSnapRespectsMinimumAndLeavesDistantSeamsAlone` — Windows equivalent/evidence: pending.
- [ ] `testNativeWidthResizeChangesOnlyItsLocalRow` — Windows equivalent/evidence: pending.
- [ ] `testNativeHeightResizeChangesOnlyItsLocalColumn` — Windows equivalent/evidence: pending.
- [ ] `testJoinedFirstTwoColumnsExposeSharedGripBesideFullHeightThirdColumn` — Windows equivalent/evidence: pending.
- [ ] `testTwoAppDividerIsSpecificAndMultiSlotDividerIsShared` — Windows equivalent/evidence: pending.
- [ ] `testSharedSectionsIncludeThreeSlotsWithoutRequiringTheFullLine` — Windows equivalent/evidence: pending.
- [ ] `testRemovingPlanningPreferencesPreservesExactFittedGeometry` — Windows equivalent/evidence: pending.
- [ ] `testCachePreservesHandlesAndInvalidatesEveryGeometryInput` — Windows equivalent/evidence: pending.
- [ ] `testGripInkSeparatesShortPillsWithoutChangingLargerHitTargets` — Windows equivalent/evidence: pending.
- [ ] `testRepeatedGeometryBenchmark` — Windows equivalent/evidence: pending.
- [ ] `testMovingAnExistingJoinedGripDoesNotReplaySnapCue` — Windows equivalent/evidence: pending.

## Native harness sources

Read the full check bodies and fixture setup, not just labels. Port lifecycle and geometry expectations using disposable HWND fixtures; replace OS-specific permission and shell operations with Windows equivalents.

- [NativeInteractionSmoke.swift](../../macos/Sources/BentoMac/NativeInteractionSmoke.swift)
- [ResizeHandleSmoke.swift](../../macos/Sources/BentoMac/ResizeHandleSmoke.swift)
- [DesktopSessionSmoke.swift](../../macos/Sources/BentoMac/DesktopSessionSmoke.swift)
- [ExternalAXSmoke.swift](../../macos/Sources/BentoMac/ExternalAXSmoke.swift)

Native coverage to preserve: gesture release/cancel and rollback; stale focus; settings exclusions; cached preview geometry; real accepted bounds; admission/overflow; repeated work-area changes; close/minimize; Pause and resume; overview suppression; helper layering; fullscreen reservations; update retry; and shutdown without window writes. See ACCEPTANCE.md for explicit Windows scenarios.
