import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AsyncTests.allTests),
        testCase(FutureTests.allTests),
        testCase(MutexTests.allTests),
    ]
}
#endif
