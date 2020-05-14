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

import Foundation

// ------------------------------------------
/**
 `Mutex` is a thin wrapper around `DispatchSemaphore` to provide an interface suitable for the special
 case of mutual exclusion.
 
 Although methods are provided to separately lock and unlock the mutex for special cases in which it is
 necessary to use them in a way that locking and unlocking is  not so easily nested, the normal use case is to
 call `withLock()` or `withAttemptedLock()` to protect data shared between threads.
 
 The following `SharedStack` implementation illustrates a simple use case:
 
        class SharedStack<T> {
            private let mutex = Mutex()
            private var contents = [T]()
 
            var top: T? {
                return mutex.withLock {
                    return contents.last
                }
            }
 
            func push(_ value: T) {
                mutex.withLock {
                    contents.append(value)
                }
            }
 
            func pop() -> T? {
                return mutex.withLock {
                    return contents.isEmpty
                        ? nil
                        : contents.removeLast()
                }
            }
        }
 */
public class Mutex
{
	private var semaphore = DispatchSemaphore(value: 1)
    
    public enum MutexError: Error {
        case lockFailed
    }
    
	// ------------------------------------------
    /**
     Block until a lock on this `Mutex` can be obtained and then lock it.
     
     Normally you should call `withLock` instead of `lock`/`tryLock` and `unlock`, because
     `lock` does not guarantee that it is balanaced with an `unlock`; however, in some special cases it
     may be necessary to interleve locking and unlocking of different mutexes, which can only be done if the
     explicit `lock`, `tryLock` and `unlock` methods are provided.
     
     - Important: Each call to `lock` must be balanced with a call to `unlock` before  this `Mutex`
        is deinitialized.
     */
	public func lock() {
        semaphore.wait(timeout: .distantFuture)
    }
    
    // ------------------------------------------
    /**
     Attempt to acquire a lock on this `Mutex` waiting only up to the specified time-out time specified as a
     `DispatchTime`
     
     Normally you should call `withAttemptedLock`  instead of `lock`/`tryLock` and `unlock`,
     because `tryLock` does not guarantee that is balanaced with an `unlock`; however, in some
     special cases it may be necessary to interleve locking and unlocking of different mutexes, which can
     only be done if the explicit `lock`, `tryLock` and `unlock` methods are provided.
     
     - Parameter deadline: `DispatchTime` to wait until for a lock before timing out.  Default
        value is `DispatchTime.now()`
     
     - Returns: On successfully obtaining the lock within the specified time-out period, this method
        returns `true`.  On failure it returns `false`
     
     - Important: if `tryLock` succeeds, you **must** balance it with an call to `unlock` before
        this `Mutex` is deinitialized.  If `tryLock` fails, you must **not** call `unlock` without first
        obtaining a successful lock.
     */
    public func tryLock(deadline: DispatchTime = .now()) -> Bool
    {
        switch semaphore.wait(timeout: deadline)
        {
            case .success:
                return true
            
            case .timedOut:
                return false
        }
    }
    
    // ------------------------------------------
    /**
     Attempt to acquire a lock on this `Mutex` waiting only for the the specified time-out interval as a
     `DispatchTimeInterval`

     Normally you should call `withAttemptedLock`  instead of `lock`/`tryLock` and `unlock`,
     because `tryLock` does not guarantee that is balanaced with an `unlock`; however, in some
     special cases it may be necessary to interleve locking and unlocking of different mutexes, which can
     only be done if the explicit `lock`, `tryLock` and `unlock` methods are provided.
     
     - Parameter timeout: `DispatchTimeInterval` to wait for a lock before timing out.
     
     - Returns: On successfully obtaining the lock within the specified time-out period, this method
        returns `true`.  On failure it returns `false`
     
     - Important: if `tryLock` succeeds, you **must** balance it with an call to `unlock` before
        this `Mutex` is deinitialized.  If `tryLock` fails, you must **not** call `unlock` without first
        obtaining a successful lock.
     */
    @inlinable
    public func tryLock(timeout: DispatchTimeInterval) -> Bool {
        return tryLock(deadline: .now() + timeout)
    }
    
    // ------------------------------------------
    /**
     Attempt to acquire a lock on this `Mutex` waiting only for the specified time-out period in seconds

     Normally you should call `withAttemptedLock`  instead of `lock`/`tryLock` and `unlock`,
     because `tryLock` does not guarantee that is balanaced with an `unlock`; however, in some
     special cases it may be necessary to interleve locking and unlocking of different mutexes, which can
     only be done if the explicit `lock`, `tryLock` and `unlock` methods are provided.
     
     - Parameter seconds: Seconds  to wait for a lock before timing out.
     
     - Returns: On successfully obtaining the lock within the specified time-out period, this method
        returns `true`.  On failure it returns `false`
     
     - Important: if `tryLock` succeeds, you **must** balance it with an call to `unlock` before
        this `Mutex` is deinitialized.  If `tryLock` fails, you must **not** call `unlock` without first
        obtaining a successful lock.
     */
    @inlinable
    public func tryLock(seconds: TimeInterval) -> Bool {
        return tryLock(timeout: .nanoseconds(Int(seconds * 1_e+9)))
    }

    // ------------------------------------------
    /**
     Unlock this `Mutex`.
     
     Normally you should call `withLock` or `withAttemptedLock` instead of `lock`/`tryLock`
     and `unlock`, because `unlock` does not guarantee that the `lock` or successful `tryLock`
     was called to be balanaced with an `unlock`; however, in some special cases it may be necessary
     to interleve locking and unlocking of different mutexes, which can only be done if the explicit `lock`,
     `tryLock` and `unlock` methods are provided.
     
     - Important: `unlock` must be called to balance out a call to `lock` before this `Mutex` is
        deinitialized.
     */
	public func unlock()
    {
        semaphore.signal()
    }
	
    // ------------------------------------------
    /**
     Wrap execution of a closure  by locking this mutex on entry and unlocking on exit, whether the exit
     occurs by `return` or `throw`
     
     This method blocks until a lock is acquired.
     
     - Parameter code: Closure to execute with this `Mutex` locked.
     
     - Returns: The value returned by `code`.
     
     - Throws: This method an error thrown by `code`
     */
    @inlinable
    public func withLock<T>(_ code:() throws -> T) rethrows -> T
    {
        lock()
        defer { unlock() }
        return try code()
    }
    
    // ------------------------------------------
    /**
     Wrap execution of a closure by locking this mutex on entry and unlocking on exit, whether the exit
     occurs by `return` or `throw`
     
     - Parameters:
         - deadline: `DispatchTime` to wait until for a lock before timing out.  Default value is
            `DispatchTime.now()`
         - code: Closure to exceute with this `Mutex` locked.
     
     - Returns: The value returned by `code`.
     
     - Throws: This method throws any error thrown by `code`, or `MutexError.lockFailed` if the
        lock could not be obtained in the specified time-out period.  If `MutexError.lockFailed` is
        thrown, `code` is not executed.
     */
    @inlinable
    public func withAttemptedLock<T>(
        deadline: DispatchTime = .now(),
        _ code:() throws -> T) throws -> T
    {
        guard tryLock() else { throw MutexError.lockFailed }
        defer { unlock() }
        return try code()
    }
    
    // ------------------------------------------
    /**
     Wrap execution of a closure by locking this mutex on entry and unlocking on exit, whether the exit
     occurs by `return` or `throw`
     
     - Parameters:
         - timeout: `DispatchTimeInterval` to wait for a lock before timing out.  Default value is
            `.nanoseconds(0)`
         - code: Closure to exceute with this `Mutex` locked.
     
     - Returns: The value returned by `code`.
     
     - Throws: This method throws any error thrown by `code`, or `MutexError.lockFailed` if the
        lock could not be obtained in the specified time-out period.  If `MutexError.lockFailed` is
        thrown, `code` is not executed.
     */
    @inlinable
    public func withAttemptedLock<T>(
        timeout: DispatchTimeInterval = .nanoseconds(0),
        _ code:() throws -> T) throws -> T
    {
        return try withAttemptedLock(deadline: .now() + timeout, code)
    }
    
    // ------------------------------------------
    /**
     Wrap execution of a closure by locking this mutex on entry and unlocking on exit, whether the exit
     occurs by `return` or `throw`
     
     - Parameters:
         - seconds: `TimeInterval` to wait for a lock before timing out.  Default value is `0`
         - code: Closure to exceute with this `Mutex` locked.
     
     - Returns: The value returned by `code`.
     
     - Throws: This method throws any error thrown by `code`, or `MutexError.lockFailed` if the
        lock could not be obtained in the specified time-out period.  If `MutexError.lockFailed` is
        thrown, `code` is not executed.
     */
    @inlinable
    public func withAttemptedLock<T>(
        seconds: TimeInterval = 0,
        _ code:() throws -> T) throws -> T
    {
        return try withAttemptedLock(
            timeout: .nanoseconds(Int(seconds * 1_e+9)),
            code
        )
    }
}
