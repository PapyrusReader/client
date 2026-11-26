// Patrol supplies these flags when it launches its Dart test runner.
#if defined(FULL_ISOLATION) && defined(CLEAR_PERMISSIONS)
@import XCTest;
@import patrol;
@import ObjectiveC.runtime;

#if !defined(PATROL_INTEGRATION_TEST_IOS_RUNNER)
#import "PatrolIntegrationTestIosRunner.h"
#endif

PATROL_INTEGRATION_TEST_IOS_RUNNER(RunnerUITests)
#endif
