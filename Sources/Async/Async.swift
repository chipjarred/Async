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
/// Base name for Async framework private/internal `DispatchQueues` based on process information
fileprivate let gcdQueueBaseName: String =
{
    let processInfo = ProcessInfo.processInfo
    return processInfo.processName + ".pid_\(processInfo.processIdentifier)"
}()


// ------------------------------------------
/// Create a dispatch queue name based on the current process information
fileprivate func createAsyncDispatchQueueName(_ suffix: String) -> String {
    return gcdQueueBaseName + suffix
}

/// `DispatchQueue` used by the global `async(afterSeconds:)` function.
fileprivate let _concurrentQueue = DispatchQueue(
    label: createAsyncDispatchQueueName(".concurrentQueue"),
    attributes: .concurrent
)

/// `DispatchQueue` used by `Future` handlers and `timeout` modifier
internal let futureHandlerQueue = DispatchQueue(
    label: createAsyncDispatchQueueName(".futureHandlerQueue"),
    attributes: .concurrent
)

// MARK:- Dispatch Queue Extension
// ------------------------------------------
public extension DispatchQueue
{
    /// Private dispatch queue used by the global `async(afterSeconds:)` function.
    static var asyncDefault: DispatchQueue {
        return _concurrentQueue
    }
    
    // ------------------------------------------
    /**
     Execute a closure asynchronously on this `DispatchQueue` after a delay, returning a `Future`
     
     - Parameters:
        - delay: Number of seconds to delay executing `executionBlock`
        - qos: the QoS at which the work item should be executed.  Defaults to
            `DispatchQoS.unspecified`.
        - flags: flags that control the execution environment of the work item.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` that will contain either the value returned by the closure, or an `Error`
        thrown by it.
     */
    @inlinable
    final func async<T>(
        afterSeconds delay:TimeInterval,
        qos: DispatchQoS = .unspecified,
        flags: DispatchWorkItemFlags = [],
        _ executionBlock:@escaping () throws -> T) -> Future<T>
    {
        return self.async(
            afterInterval: .nanoseconds(Int(delay * 1_e+9)),
            qos: qos,
            flags: flags,
            executionBlock
        )
    }
    
    // ------------------------------------------
    /**
     Execute a closure asynchronously on this `DispatchQueue` after a delay, returning a `Future`
     
     - Parameters:
        - delay: `DispatchTimeInterval` to delay executing `executionBlock`.
            Defaults to 0 nanoseconds
        - qos: the QoS at which the work item should be executed.  Defaults to
            `DispatchQoS.unspecified`.
        - flags: flags that control the execution environment of the work item.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` that will contain either the value returned by the closure, or an `Error`
        thrown by it.
     */
    @inlinable
    final func async<T>(
        afterInterval delay:DispatchTimeInterval,
        qos: DispatchQoS = .unspecified,
        flags: DispatchWorkItemFlags = [],
        _ executionBlock:@escaping () throws -> T) -> Future<T>
    {
        return self.async(
            afterDeadline: .now() + delay,
            qos: qos,
            flags: flags,
            executionBlock
        )
    }

    // ------------------------------------------
    /**
     Execute a closure asynchronously on this `DispatchQueue` immediately or after a deadline,
     returning a `Future`
     
     - Parameters:
        - deadline: `Date` to wait for before  executing `executionBlock`
        - qos: the QoS at which the work item should be executed.  Defaults to
            `DispatchQoS.unspecified`.
        - flags: flags that control the execution environment of the work item.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` that will contain either the value returned by the closure, or an `Error`
        thrown by it.
     */
    @inlinable
    final func async<T>(
        afterDeadline deadline: Date,
        qos: DispatchQoS = .unspecified,
        flags: DispatchWorkItemFlags = [],
        _ executionBlock:@escaping () throws -> T) -> Future<T>
    {
        return self.async(
            afterSeconds: max(deadline.timeIntervalSince(Date()), 0),
            qos: qos,
            flags: flags,
            executionBlock
        )
    }
    
    // ------------------------------------------
    /**
     Execute a closure asynchronously on this `DispatchQueue` immediately or after a deadline,
     returning a `Future`
     
     - Parameters:
        - deadline: `DispatchTime` to wait for before  executing `executionBlock`.  `nil`
            indicates to run as soon as possible.
        - qos: the QoS at which the work item should be executed.  Defaults to
            `DispatchQoS.unspecified`.
        - flags: flags that control the execution environment of the work item.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` that will contain either the value returned by the closure, or an `Error`
        thrown by it.
     */
    @inlinable
    final func async<T>(
        afterDeadline deadline:DispatchTime? = nil,
        qos: DispatchQoS = .unspecified,
        flags: DispatchWorkItemFlags = [],
        _ executionBlock:@escaping () throws -> T) -> Future<T>
    {
        let promise = Promise<T>()
        
        if let deadline = deadline
        {
            self.asyncAfter(
                deadline: deadline,
                qos: qos,
                flags: flags)
            {
                promise.set(from: executionBlock)
            }
        }
        else
        {
            self.async(group: nil, qos: qos, flags: flags) {
                promise.set(from: executionBlock)
            }
        }

        return promise.future
    }

    // ------------------------------------------
    /**
     Execute a closure synchronously on this `DispatchQueue`, returning a `Future`
     
     This method blocks until the closure completes, including the specified delay.

     - Note: This method is provided to aid in debugging timing issues.

     - Parameters:
        - delay: Number of seconds to delay executing `executionBlock`.
        - qos: the QoS at which the work item should be executed.  Defaults to
            `DispatchQoS.unspecified`.
        - flags: flags that control the execution environment of the work item.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
        by it.
     */
    final func sync<T>(
        afterSeconds delay:TimeInterval,
        qos: DispatchQoS = .unspecified,
        flags: DispatchWorkItemFlags = [],
        _ executionBlock:@escaping () throws -> T) -> Future<T>
    {
        return sync(
            afterInterval: .nanoseconds(Int(delay * 1_e+9)),
            qos: qos,
            flags: flags,
            executionBlock
        )
    }
    
    // ------------------------------------------
    /**
     Execute a closure synchronously on this `DispatchQueue`, returning a `Future`
     
     This method blocks until the closure completes, including the specified delay.

     - Note: This method is provided to aid in debugging timing issues.

     - Parameters:
        - delay: `DispatchTimeInterval` to delay executing `executionBlock`.
        - qos: the QoS at which the work item should be executed.  Defaults to
            `DispatchQoS.unspecified`.
        - flags: flags that control the execution environment of the work item.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
        by it.
     */
    @inlinable
    final func sync<T>(
        afterInterval delay:DispatchTimeInterval,
        qos: DispatchQoS = .unspecified,
        flags: DispatchWorkItemFlags = [],
        _ executionBlock:@escaping () throws -> T) -> Future<T>
    {
        return sync(
            afterDeadline: .now() + delay,
            qos: qos,
            flags: flags,
            executionBlock
        )
    }

    // ------------------------------------------
    /**
     Execute a closure synchronously on this `DispatchQueue` immediately or after a deadline,
     returning a `Future`
     
     - Parameters:
        - deadline: `Date` to wait for before  executing `executionBlock`
        - qos: the QoS at which the work item should be executed.  Defaults to
            `DispatchQoS.unspecified`.
        - flags: flags that control the execution environment of the work item.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` that will contain either the value returned by the closure, or an `Error`
        thrown by it.
     */
    @inlinable
    final func sync<T>(
        afterDeadline deadline: Date,
        qos: DispatchQoS = .unspecified,
        flags: DispatchWorkItemFlags = [],
        _ executionBlock:@escaping () throws -> T) -> Future<T>
    {
        return self.sync(
            afterSeconds: max(deadline.timeIntervalSince(Date()), 0),
            qos: qos,
            flags: flags,
            executionBlock
        )
    }
    // ------------------------------------------
    /**
     Execute a closure synchronously on this `DispatchQueue` immediately or after a deadline,
     returning a `Future`
     
     This method blocks until the closure completes, including any delay for the deadline.

     - Note: This method is provided to aid in debugging timing issues.
     
     - Parameters:
        - deadline: `DispatchTime` to wait for before  executing `executionBlock`.  `nil`
            indicates to run immediately.
        - qos: the QoS at which the work item should be executed.  Defaults to
            `DispatchQoS.unspecified`.
        - flags: flags that control the execution environment of the work item.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
        by it.
     */
    @inlinable
    final func sync<T>(
        afterDeadline deadline:DispatchTime? = nil,
        qos: DispatchQoS = .unspecified,
        flags: DispatchWorkItemFlags = [],
        _ executionBlock:@escaping () throws -> T) -> Future<T>
    {
        if let deadline = deadline
        {
            let deadlineSemaphore = DispatchSemaphore(value: 0)
            let _ = deadlineSemaphore.wait(timeout: deadline)
        }
        
        let promise = Promise<T>()
        promise.set(from: executionBlock)
        return promise.future
    }
}

// MARK:- Global Functions
// ------------------------------------------
/**
 Execute a closure asynchronously on the global concurrent `DispatchQueue` after a delay, returning a
 `Future`
 
 - Parameters:
    - delay: Number of seconds to delay executing `executionBlock`
    - qos: the QoS at which the work item should be executed.  Defaults to
        `DispatchQoS.unspecified`.
    - flags: flags that control the execution environment of the work item.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` that will contain either the value returned by the closure, or an `Error`
    thrown by it.
 */
@inlinable
public func async<T>(
    afterSeconds delay:TimeInterval,
    qos: DispatchQoS = .unspecified,
    flags: DispatchWorkItemFlags = [],
    _ executionBlock:@escaping () throws -> T) -> Future<T>
{
    return DispatchQueue.asyncDefault.async(
        afterSeconds: delay,
        qos: qos,
        flags: flags,
        executionBlock
    )
}

// ------------------------------------------
/**
 Execute a closure asynchronously on the global concurrent `DispatchQueue` after a delay, returning a
 `Future`
 
 - Parameters:
    - delay: `DispatchTimeInterval` to delay executing `executionBlock`.
        Defaults to 0 nanoseconds
    - qos: the QoS at which the work item should be executed.  Defaults to
        `DispatchQoS.unspecified`.
    - flags: flags that control the execution environment of the work item.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` that will contain either the value returned by the closure, or an `Error`
    thrown by it.
 */
@inlinable
public func async<T>(
    afterInterval delay:DispatchTimeInterval,
    qos: DispatchQoS = .unspecified,
    flags: DispatchWorkItemFlags = [],
    _ executionBlock:@escaping () throws -> T) -> Future<T>
{
    return DispatchQueue.asyncDefault.async(
        afterInterval: delay,
        qos: qos,
        flags: flags,
        executionBlock
    )
}

// ------------------------------------------
/**
 Execute a closure asynchronously on the global concurrent `DispatchQueue` immediately or after a
 specified deadline, returning a `Future`
 
 - Parameters:
    - deadline: `Date` to wait for before  executing `executionBlock`.
    - qos: the QoS at which the work item should be executed.  Defaults to
        `DispatchQoS.unspecified`.
    - flags: flags that control the execution environment of the work item.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` that will contain either the value returned by the closure, or an `Error`
    thrown by it.
 */
@inlinable
public func async<T>(
    afterDeadline deadline: Date,
    qos: DispatchQoS = .unspecified,
    flags: DispatchWorkItemFlags = [],
    _ executionBlock:@escaping () throws -> T) -> Future<T>
{
    return DispatchQueue.asyncDefault.async(
        afterDeadline: deadline,
        qos: qos,
        flags: flags,
        executionBlock
    )
}

// ------------------------------------------
/**
 Execute a closure asynchronously on the global concurrent `DispatchQueue` immediately or after a
 specified deadline, returning a `Future`
 
 - Parameters:
    - deadline: `DispatchTime` to wait for before  executing `executionBlock`.  `nil`
        indicates to run as soon as possible.
    - qos: the QoS at which the work item should be executed.  Defaults to
        `DispatchQoS.unspecified`.
    - flags: flags that control the execution environment of the work item.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` that will contain either the value returned by the closure, or an `Error`
    thrown by it.
 */
@inlinable
public func async<T>(
    afterDeadline deadline: DispatchTime? = nil,
    qos: DispatchQoS = .unspecified,
    flags: DispatchWorkItemFlags = [],
    _ executionBlock:@escaping () throws -> T) -> Future<T>
{
    return DispatchQueue.asyncDefault.async(
        afterDeadline: deadline,
        qos: qos,
        flags: flags,
        executionBlock
    )
}

// ------------------------------------------
/**
 Execute a closure synchronously, returning a `Future`
 
 This function blocks until the closure completes, including the specified delay.

 - Note: This funciton is provided to aid in debugging timing issues.

 - Parameters:
    - delay: Number of seconds to delay executing `executionBlock`.
    - qos: the QoS at which the work item should be executed.  Defaults to
        `DispatchQoS.unspecified`.
    - flags: flags that control the execution environment of the work item.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
    by it.
 */
@inlinable
func sync<T>(
    afterSeconds delay: TimeInterval,
    qos: DispatchQoS = .unspecified,
    flags: DispatchWorkItemFlags = [],
    _ executionBlock:@escaping () throws -> T) -> Future<T>
{
    return DispatchQueue.asyncDefault.sync(
        afterSeconds: delay,
        qos: qos,
        flags: flags,
        executionBlock
    )
}

// ------------------------------------------
/**
 Execute a closure synchronously on this `DispatchQueue`, returning a `Future`
 
 This function blocks until the closure completes, including the specified delay.

 - Note: This method is provided to aid in debugging timing issues.

 - Parameters:
    - delay: `DispatchTimeInterval` to delay executing `executionBlock`.
    - qos: the QoS at which the work item should be executed.  Defaults to
        `DispatchQoS.unspecified`.
    - flags: flags that control the execution environment of the work item.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
    by it.
 */
@inlinable
public func sync<T>(
    afterInterval delay: DispatchTimeInterval,
    qos: DispatchQoS = .unspecified,
    flags: DispatchWorkItemFlags = [],
    _ executionBlock:@escaping () throws -> T) -> Future<T>
{
    return DispatchQueue.asyncDefault.sync(
        afterInterval: delay,
        qos: qos,
        flags: flags,
        executionBlock
    )
}

// ------------------------------------------
/**
 Execute a closure synchronously on this `DispatchQueue` immediately or after a deadline,
 returning a `Future`
 
 This function blocks until the closure completes, including any delay for the deadline.
 
 - Note: This method is provided to aid in debugging timing issues.
 
 - Parameters:
    - deadline: `Date` to wait for before  executing `executionBlock`.
    - qos: the QoS at which the work item should be executed.  Defaults to
        `DispatchQoS.unspecified`.
    - flags: flags that control the execution environment of the work item.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
    by it.
 */
@inlinable
public func sync<T>(
    afterDeadline deadline: Date,
    qos: DispatchQoS = .unspecified,
    flags: DispatchWorkItemFlags = [],
    _ executionBlock:@escaping () throws -> T) -> Future<T>
{
    return DispatchQueue.asyncDefault.sync(
        afterDeadline: deadline,
        qos: qos,
        flags: flags,
        executionBlock
    )
}

// ------------------------------------------
/**
 Execute a closure synchronously on this `DispatchQueue` immediately or after a deadline,
 returning a `Future`
 
 This function blocks until the closure completes, including any delay for the deadline.
 
 - Note: This method is provided to aid in debugging timing issues.
 
 - Parameters:
    - deadline: `DispatchTime` to wait for before  executing `executionBlock`.  `nil`
        indicates to run immediately.
    - qos: the QoS at which the work item should be executed.  Defaults to
        `DispatchQoS.unspecified`.
    - flags: flags that control the execution environment of the work item.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
    by it.
 */
@inlinable
public func sync<T>(
    afterDeadline deadline:DispatchTime? = nil,
    qos: DispatchQoS = .unspecified,
    flags: DispatchWorkItemFlags = [],
    _ executionBlock:@escaping () throws -> T) -> Future<T>
{
    return DispatchQueue.asyncDefault.sync(
        afterDeadline: deadline,
        qos: qos,
        flags: flags,
        executionBlock
    )
}

