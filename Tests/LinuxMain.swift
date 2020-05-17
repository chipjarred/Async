import XCTest

import AsyncTests

var tests = [XCTestCaseEntry]()
tests += AsyncTests.allTests()
tests += FutureTests.allTests()
tests += MutexTests.allTests()
XCTMain(tests)
