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
/**
 Because of their nature, testing mutexes is notoriously difficult, and would require long-running tests that try to
 detect data races or deadlocks.  Yet unit tests should be fast, otherwise they tend not to be run.  Under the
 assumption that some tests is better than no tests, the following tests don't try to tests for those concurrency
 issues at scale, as would be needed for thorough testing, but rather that locks and unlocks happen as
 expected in a synchronous context, and for a few contrived asyncrhonous cases.
 */
class MutexTests: XCTestCase
{
    // ------------------------------------------
    private func noOp() { }
    
    // ------------------------------------------
    func test_new_mutex_can_be_locked()
    {
        let mutex = Mutex()
        
        let lockSucceeded = mutex.tryLock(deadline: .now())
        
        defer { if lockSucceeded { mutex.unlock() } }

        XCTAssertTrue(lockSucceeded)
    }
    
    // ------------------------------------------
    func test_locked_mutex_prevents_subsequent_lock()
    {
        let mutex = Mutex()
        
        let secondLockSucceeded =  mutex.withLock {
            return mutex.tryLock(deadline: .now())
        }
        
        defer { if secondLockSucceeded { mutex.unlock() } }

        XCTAssertFalse(secondLockSucceeded)
    }
    
    // ------------------------------------------
    func test_locked_then_unlocked_mutex_allows_subsequent_lock()
    {
        let mutex = Mutex()
        
        mutex.withLock { noOp() }
            
        let secondLockSucceeded = mutex.tryLock(deadline: .now())
        defer { if secondLockSucceeded { mutex.unlock() } }

        XCTAssertTrue(secondLockSucceeded)
    }
    
    // ------------------------------------------
    /**
     This test seems a bit weird, because it's using `DispatchSemaphore` to coordinate between two
     asynchronous tasks to lock a `Mutex` in one while a lock is being held in the other, yet `Mutex` is
     itself implemented in terms of `DispatchSemaphore`.  The usage is different though, since the
     `DispatchSempahore` in the `Mutex` is acting as a guard against simultaneous access, while the
     other `DispatchSemaphore` coordinates the two tasks so they behave as co-routines to guarantee
     that one tries to lock the mutex when it is already locked by the other.
     */
    func test_mutex_locked_in_one_async_task_prevents_another_async_task_from_obtaining_lock()
    {
        let mutex = Mutex()
                
        let bSem = DispatchSemaphore(value: 0)

        var timeout: DispatchTime {
            return .now() + .milliseconds(100)
        }
        // Task A: This is our actual test
        let taskA = async
        {
            // wait for Task B to obtain the lock.  This should succeed
            XCTAssertEqual(
                bSem.wait(timeout: timeout),
                .success, "Task B never didn't lock in time"
            )
            
            /*
             Now that B has locked the mutex, A's attempt to lock it should fail
             */
            do {
                try mutex.withAttemptedLock(deadline: .now()) { }
                XCTFail("Task A obtained lock that it shouldn't have")
            }
            catch let error as Mutex.MutexError {
                XCTAssertEqual(error, .lockFailed)
            }
            catch
            {
                XCTFail(
                    "Task A got unexpected error trying to obtain lock: "
                    + "\(type(of: error)) = \(error.localizedDescription)"
                )
            }
            
        }
        
        /*
         Task B: This task locks the mutex and then "sleeps" so that Task A
         can try to obtain a lock from a mutex that has been locked.
         */
        let taskB = async
        {
            mutex.withLock
            {
                // Signal to Task A that Task B has obtained lock
                bSem.signal()
                
                // Now just sleep long enough to allow Task A to attempt lock
                let _ = DispatchSemaphore(value: 0).wait(timeout: timeout)
            }
        }
        
        taskA.wait()
        taskB.wait()
    }
    
    // ------------------------------------------
    /**
     This test seems a bit weird, because it's using `DispatchSemaphore` to coordinate between two
     asynchronous tasks to lock a `Mutex` in one while a lock is being held in the other, yet `Mutex` is
     itself implemented in terms of `DispatchSemaphore`.  The usage is different though, since the
     `DispatchSempahore` in the `Mutex` is acting as a guard against simultaneous access, while the
     other `DispatchSemaphore` coordinates the two tasks so they behave as co-routines to guarantee
     that one tries to lock the mutex only after the other has locked and unlocked.
     */
    func test_mutex_unlocked_in_one_async_task_allows_another_async_task_to_obtain_lock()
    {
        let mutex = Mutex()
                
        let bSem = DispatchSemaphore(value: 0)

        var timeout: DispatchTime {
            return .now() + .milliseconds(100)
        }
        // Task A: This is our actual test
        let taskA = async
        {
            // wait for Task B to lock and then unlock.  This should succeed
            XCTAssertEqual(
                bSem.wait(timeout: timeout),
                .success, "Task B never didn't lock in time"
            )
            
            /*
             Now that B has locked and unlocked the mutex, A's attempt to lock
             it should succeed
             */
            do {
                try mutex.withAttemptedLock(deadline: .now()) { }
            }
            catch let error as Mutex.MutexError
            {
                if error != .lockFailed
                {
                    XCTFail(
                        "Task A got unexpected error trying to obtain lock: "
                        + "\(type(of: error)) = \(error.localizedDescription)"
                    )
                } else {
                    XCTFail("Task A failed to obtain lock that it should have")
                }
            }
            catch
            {
                XCTFail(
                    "Task A got unexpected error trying to obtain lock: "
                    + "\(type(of: error)) = \(error.localizedDescription)"
                )
            }
            
        }
        
        /*
         Task B: This task locks the mutex and then unlocks itm signalling to
         task A that it has done so.
         */
        let taskB = async
        {
            mutex.withLock { }
            // Signal to Task A that Task B has locked and unlocked
            bSem.signal()
        }
        
        taskA.wait()
        taskB.wait()
    }
}
