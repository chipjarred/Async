// Copyright 2020 Chip Jarred
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is furnished
// to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import XCTest
@testable import Async

// ------------------------------------------
class FutureTests: XCTestCase
{
    var futureTimeOut: DispatchTime {
        return DispatchTime.now() + DispatchTimeInterval.milliseconds(100)
    }
        
    enum TestError: Error { case error }
    
    // MARK:- Fluid API Tests
    // ------------------------------------------
    func test_future_onSuccess_handler_is_called_when_closure_returns()
    {
        let testSemaphore = DispatchSemaphore(value: 0)
    
        var successCalled = false
        var successValue = 0
        
        async { return 5 }
        .onSuccess
        {
            defer { testSemaphore.signal() }
            successCalled = true
            successValue = $0
        }
        
        let _ = testSemaphore.wait(timeout: futureTimeOut)
        
        XCTAssertTrue(successCalled)
        XCTAssertEqual(successValue, 5)
    }
    
    // ------------------------------------------
    func test_future_onSuccess_handler_is_not_called_when_closure_throws()
    {
        let testSemaphore = DispatchSemaphore(value: 0)
    
        var successCalled = false
        var successValue = 0
        var shouldThrow: Bool { true }
        
        async
        { () -> Int in
            if shouldThrow { throw TestError.error }
            return 5
        }
        .onSuccess
        {
            defer { testSemaphore.signal() }
            successCalled = true
            successValue = $0
        }
        
        let _ = testSemaphore.wait(timeout: futureTimeOut)
        
        XCTAssertFalse(successCalled)
        XCTAssertEqual(successValue, 0)
    }
    
    // ------------------------------------------
    func test_future_onFailure_handler_is_called_when_closure_throws()
    {
        let testSemaphore = DispatchSemaphore(value: 0)
    
        var failureCalled = false
        var shouldThrow: Bool { true }
        
        async
        { () -> Int in
            if shouldThrow { throw TestError.error }
            return 5
        }
        .onFailure
        { _ in
            defer { testSemaphore.signal() }
            failureCalled = true
        }
        
        let _ = testSemaphore.wait(timeout: futureTimeOut)
        
        XCTAssertTrue(failureCalled)
    }
    
    // ------------------------------------------
    func test_future_onFailure_handler_is_not_called_when_closure_returns()
    {
        let testSemaphore = DispatchSemaphore(value: 0)
    
        var failureCalled = false
        var shouldThrow: Bool { false }
        
        async
        { () -> Int in
            if shouldThrow { throw TestError.error }
            return 5
        }
        .onFailure
        { _ in
            defer { testSemaphore.signal() }
            failureCalled = true
        }
        
        let _ = testSemaphore.wait(timeout: futureTimeOut)
        
        XCTAssertFalse(failureCalled)
    }
    
    // ------------------------------------------
    func test_future_onSuccess_handler_is_called_when_closure_returns_and_onFailure_handler_is_not()
    {
        let testSemaphore = DispatchSemaphore(value: 0)
    
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { false }

        async { if shouldThrow { throw TestError.error } }
        .onSuccess
        {
            defer { testSemaphore.signal() }
            successCalled = true
        }
        .onFailure
        { _ in
            defer { testSemaphore.signal() }
            failureCalled = true
        }

        let _ = testSemaphore.wait(timeout: futureTimeOut)
        
        XCTAssertTrue(successCalled)
        XCTAssertFalse(failureCalled)
    }
    
    // ------------------------------------------
    func test_future_onFailure_handler_is_called_when_closure_throws_and_onSuccess_handler_is_not()
    {
        let testSemaphore = DispatchSemaphore(value: 0)
    
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { true }

        async { if shouldThrow { throw TestError.error } }
        .onSuccess
        {
            defer { testSemaphore.signal() }
            successCalled = true
        }
        .onFailure
        { _ in
            defer { testSemaphore.signal() }
            failureCalled = true
        }

        let _ = testSemaphore.wait(timeout: futureTimeOut)
        
        XCTAssertFalse(successCalled)
        XCTAssertTrue(failureCalled)
    }
    
    // ------------------------------------------
    func test_future_with_value_already_set_calls_onSuccess_handler_when_added()
    {
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { false }

        sync { if shouldThrow { throw TestError.error } }
        .onSuccess { successCalled = true }
        .onFailure { _ in failureCalled = true }

        XCTAssertTrue(successCalled)
        XCTAssertFalse(failureCalled)
    }
    
    // ------------------------------------------
    func test_future_with_error_already_set_calls_onFailure_handler_when_added()
    {
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { true }

        sync { if shouldThrow { throw TestError.error } }
        .onSuccess { successCalled = true }
        .onFailure { _ in failureCalled = true }

        XCTAssertFalse(successCalled)
        XCTAssertTrue(failureCalled)
    }
    
    // ------------------------------------------
    func test_future_onCompletion_handler_is_called_with_a_success_Result_when_closure_returns()
    {
        let testSemaphore = DispatchSemaphore(value: 0)
    
        var resultFailure = false
        var resultSuccess = false
        var shouldThrow: Bool { false }

        async { if shouldThrow { throw TestError.error } }
        .onCompletion
        {
            defer { testSemaphore.signal() }
            switch $0
            {
                case .success(_): resultSuccess = true
                case .failure(_): resultFailure = true
            }
        }

        let _ = testSemaphore.wait(timeout: futureTimeOut)
        
        XCTAssertTrue(resultSuccess)
        XCTAssertFalse(resultFailure)
    }
    
    // ------------------------------------------
    func test_future_onCompletion_handler_is_called_with_a_failure_Result_when_closure_throws()
    {
        let testSemaphore = DispatchSemaphore(value: 0)
    
        var resultFailure = false
        var resultSuccess = false
        var shouldThrow: Bool { true }

        async { if shouldThrow { throw TestError.error } }
        .onCompletion
        {
            defer { testSemaphore.signal() }
            switch $0
            {
                case .success(_): resultSuccess = true
                case .failure(_): resultFailure = true
            }
        }

        let _ = testSemaphore.wait(timeout: futureTimeOut)
        
        XCTAssertFalse(resultSuccess)
        XCTAssertTrue(resultFailure)
    }
    
    // ------------------------------------------
    func test_future_with_value_already_set_calls_onCompletion_handler_when_added()
    {
        var resultFailure = false
        var resultSuccess = false
        var shouldThrow: Bool { false }

        sync { if shouldThrow { throw TestError.error } }
        .onCompletion
        {
            switch $0
            {
                case .success(_): resultSuccess = true
                case .failure(_): resultFailure = true
            }
        }

        XCTAssertTrue(resultSuccess)
        XCTAssertFalse(resultFailure)
    }
    
    // ------------------------------------------
    func test_future_with_error_already_set_calls_onCompletion_handler_when_added()
    {
        var resultFailure = false
        var resultSuccess = false
        var shouldThrow: Bool { true }

        sync { if shouldThrow { throw TestError.error } }
        .onCompletion
        {
            switch $0
            {
                case .success(_): resultSuccess = true
                case .failure(_): resultFailure = true
            }
        }

        XCTAssertFalse(resultSuccess)
        XCTAssertTrue(resultFailure)
    }
    
    // ------------------------------------------
    func test_future_onSuccess_handler_is_called_and_failure_handler_is_not_when_closure_has_timeout_modifier_but_does_not_timeout()
    {
    
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { false }
        
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }
        var timeOut: DispatchTime {
            return .now() + .milliseconds(200)
        }

        async
        {
            if shouldThrow { throw TestError.error }
        }
        .onSuccess { successCalled = true }
        .onFailure
        { error in
            failureCalled = true
            XCTAssertEqual(error as? FutureError, FutureError.timeOut)
        }
        .timeout(deadline: timeOut)

        let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)

        XCTAssertTrue(successCalled)
        XCTAssertFalse(failureCalled)
    }
    
    // ------------------------------------------
    func test_future_onSuccess_handler_is_not_called_when_closure_times_out_but_failure_handler_is_when_added_before_timeout_occurs()
    {
    
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { false }
        
        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        async
        {
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            if shouldThrow { throw TestError.error }
        }
        .onSuccess { successCalled = true }
        .onFailure
        { error in
            failureCalled = true
            XCTAssertEqual(error as? FutureError, FutureError.timeOut)
        }
        .timeout(deadline: timeOut)

        let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)

        XCTAssertFalse(successCalled)
        XCTAssertTrue(failureCalled)
    }

    // ------------------------------------------
    func test_future_onSuccess_handler_is_not_called_when_closure_times_out_but_failure_handler_is_when_they_are_added_after_timeout_occurs()
    {
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { false }
        
        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        let future = async
        {
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            if shouldThrow { throw TestError.error }
        }
        .timeout(deadline: timeOut)
            
        let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)

        future.onSuccess { successCalled = true }
        .onFailure
        { error in
            failureCalled = true
            XCTAssertEqual(error as? FutureError, FutureError.timeOut)
        }

        XCTAssertFalse(successCalled)
        XCTAssertTrue(failureCalled)
    }
    
    // ------------------------------------------
    func test_future_onCompletion_handler_is_called_with_result_when_closure_has_timeout_modifier_but_does_not_timeout()
    {
    
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { false }
        
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }
        var timeOut: DispatchTime {
            return .now() + .milliseconds(200)
        }

        async
        { () -> Void in
            if shouldThrow { throw TestError.error }
        }
        .onCompletion()
        {
            switch $0
            {
                case .success(_): successCalled = true
                
                case .failure(let error):
                    failureCalled = true
                    XCTFail(
                        "Got error when expected success: \(type(of: error)) = "
                        + "\(error.localizedDescription)"
                )
            }
        }
        .timeout(deadline: timeOut)

        let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)

        XCTAssertTrue(successCalled)
        XCTAssertFalse(failureCalled)
    }
    

    // ------------------------------------------
    func test_future_onCompletion_handler_is_called_with_failure_when_closure_times_out_when_added_before_timeout_occurs()
    {
        let testSemaphore = DispatchSemaphore(value: 0)
    
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { false }
        
        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        async
        { () -> Void in
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            if shouldThrow { throw TestError.error }
        }
        .onCompletion()
        {
            switch $0
            {
                case .success(_):
                    successCalled = true
                    XCTFail("Expected time-out")
                
                case .failure(let error):
                    failureCalled = true
                    XCTAssertEqual(error as? FutureError, FutureError.timeOut)
            }
        }
        .timeout(deadline: timeOut)

        let _ = testSemaphore.wait(timeout: futureTimeOut)
        
        XCTAssertFalse(successCalled)
        XCTAssertTrue(failureCalled)
    }
    // ------------------------------------------
    func test_future_onCompletion_handler_is_called_with_failure_when_closure_times_out_but_failure_handler_is_when_added_after_timeout_occurs()
    {
        var failureCalled = false
        var successCalled = false
        var shouldThrow: Bool { false }

        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        let future = async
        {
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            if shouldThrow { throw TestError.error }
        }
        .timeout(deadline: timeOut)
            
        let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)

        future.onCompletion()
        {
            switch $0
            {
                case .success(_):
                    successCalled = true
                    XCTFail("Expected time-out")
                
                case .failure(let error):
                    failureCalled = true
                    XCTAssertEqual(error as? FutureError, FutureError.timeOut)
            }
        }
        
        XCTAssertFalse(successCalled)
        XCTAssertTrue(failureCalled)
    }

    // MARK:- Imperative Use Tests
    // ------------------------------------------
    func test_future_has_value_and_not_error_when_closure_returns()
    {
        var shouldThrow: Bool { false }

        let future = async { () -> Int in
            if shouldThrow { throw TestError.error }
            return 5
        }
        
        let value = future.value
        XCTAssertNotNil(value)
        XCTAssertEqual(value, 5)
        XCTAssertNil(future.error)
    }

    // ------------------------------------------
    func test_future_has_error_and_not_value_when_closure_throws()
    {
        var shouldThrow: Bool { true }

        let future = async { () -> Int in
            if shouldThrow { throw TestError.error }
            return 5
        }
        
        if let error = future.error
        {
            if let testError = error as? TestError {
                XCTAssertEqual(testError, TestError.error)
            }
            else { XCTFail("Wrong kind of error") }
        }
        else { XCTFail("error was nil!") }
            
        XCTAssertNil(future.value)
    }
    
    // ------------------------------------------
    func test_future_has_success_Result_when_closure_returns()
    {
        var shouldThrow: Bool { false }

        let future = async { () -> Int in
            if shouldThrow { throw TestError.error }
            return 5
        }
        
        switch future.result
        {
            case .success(let value):
                XCTAssertEqual(value, 5)
            
            case .failure(_):
                XCTFail("Got an error!")
        }
    }
    
    // ------------------------------------------
    func test_future_has_failure_Result_when_closure_throws()
    {
        var shouldThrow: Bool { true }

        let future = async { () -> Int in
            if shouldThrow { throw TestError.error }
            return 5
        }
        
        switch future.result
        {
            case .success(_):
                XCTFail("Got a value!")
            
            case .failure(let error):
                if let testError = error as? TestError {
                    XCTAssertEqual(testError, TestError.error)
                }
                else { XCTFail("Wrong kind of error") }
        }
    }
    
    // ------------------------------------------
    func test_future_getValue_method_returns_value_when_closure_returns()
    {
        var shouldThrow: Bool { false }

        let future = async { () -> Int in
            if shouldThrow { throw TestError.error }
            return 5
        }
        
        do
        {
            let value = try future.getValue()
            XCTAssertEqual(value, 5)
        }
        catch { XCTFail("Got error!") }
    }
    
    // ------------------------------------------
    func test_future_getValue_method_throws_when_closure_throws()
    {
        var shouldThrow: Bool { true }

        let future = async { () -> Int in
            if shouldThrow { throw TestError.error }
            return 5
        }
        
        do
        {
            let _ = try future.getValue()
            XCTFail("Got value!")
        }
        catch let error as TestError { XCTAssertEqual(error, TestError.error) }
        catch { XCTFail("Wrong kind of error!") }
    }
    
    // ------------------------------------------
    func test_future_has_value_and_no_error_when_has_timeout_modifier_set_but_not_triggered()
    {
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        var timeOut: DispatchTime {
            return .now() + .milliseconds(200)
        }
        
        let future = async
        { () -> Int in
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            return 5
        }
        .timeout(deadline: timeOut)
        
        let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
        
        XCTAssertEqual(future.value, 5)
        XCTAssertNil(future.error)
    }
    
    // ------------------------------------------
    func test_future_has_success_Result_when_has_timeout_modifier_set_but_not_triggered()
    {
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        var timeOut: DispatchTime {
            return .now() + .milliseconds(200)
        }

        let future = async
        { () -> Int in
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            return 5
        }
        .timeout(deadline: timeOut)
        
        let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
        
        switch future.result
        {
            case .success(let value):
                XCTAssertEqual(value, 5)
            case .failure(let error):
                XCTFail(
                    "Got error when expected success: \(type(of:error)) = "
                    + "\(error.localizedDescription))"
                )
        }
    }
    
    // ------------------------------------------
    func test_future_value_has_no_value_and_has_error_when_timeout_modifier_is_set_triggered()
    {
        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        let future = async
        { () -> Int in
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            return 5
        }
        .timeout(deadline: timeOut)
        
        let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
        
        XCTAssertNil(future.value)
        XCTAssertEqual(future.error as? FutureError, FutureError.timeOut)
    }
    
    // ------------------------------------------
    func test_future_Result_has_failure_when_timeout_modifier_is_set_triggered()
    {
        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }
        
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        let future = async
        { () -> Int in
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            return 5
        }
        .timeout(deadline: timeOut)
        
        let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
        
        switch future.result
        {
            case .success(_):
                XCTFail("Expected time-out, but got value")

            case .failure(let error):
                XCTAssertEqual(error as? FutureError, FutureError.timeOut)
        }
    }
    
    // ------------------------------------------
    func test_future_wait_with_timeout_does_not_time_out_when_closure_returns_before_time_out()
    {
        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }

        let future = async
        { () -> Int in
            return 5
        }

        XCTAssertEqual(future.wait(until: timeOut), .success)
        XCTAssertTrue(future.isReady)
        XCTAssertEqual(future.value, 5)
        XCTAssertNil(future.error)
    }
    
    // ------------------------------------------
    func test_future_wait_with_timeout_does_time_out_when_closure_returns_after_time_out()
    {
        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }
        
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        let future = async
        { () -> Int in
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            return 5
        }

        XCTAssertEqual(future.wait(until: timeOut), .timedOut)
        XCTAssertFalse(future.isReady)
        
        // This will block until future is ready because wait(until:) doesn't
        // set error to FutureError.timedOut
        XCTAssertEqual(future.value, 5)
        XCTAssertNil(future.error)
    }
    
    // ------------------------------------------
    func test_future_wait_with_timeout_does_not_time_out_when_closure_throws_before_time_out()
    {
        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }

        let future = async
        { () -> Int in
            throw TestError.error
        }

        XCTAssertEqual(future.wait(until: timeOut), .success)
        XCTAssertTrue(future.isReady)
        XCTAssertNil(future.value)
        XCTAssertEqual(future.error as? TestError, TestError.error)
    }
    
    // ------------------------------------------
    func test_future_wait_with_timeout_does_time_out_when_closure_throws_after_time_out()
    {
        var timeOut: DispatchTime {
            return .now() + .milliseconds(50)
        }
        
        var sleepTime: DispatchTime {
            return .now() + .milliseconds(100)
        }

        let future = async
        { () -> Int in
            let _ = DispatchSemaphore(value: 0).wait(timeout: sleepTime)
            throw TestError.error
        }

        XCTAssertEqual(future.wait(until: timeOut), .timedOut)
        XCTAssertFalse(future.isReady)
        
        // This will block until future is ready because wait(until:) doesn't
        // set error to FutureError.timedOut
        XCTAssertNil(future.value)
        XCTAssertEqual(future.error as? TestError, TestError.error)
    }
}
