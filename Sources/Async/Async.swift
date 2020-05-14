//
//  Async.swift
//  BTCNet2
//
//  Created by Chip Jarred on 12/8/17.
//  Copyright © 2017 Chip Jarred. All rights reserved.
//

import Foundation

fileprivate extension Bundle {
	var displayName: String? {
		return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
	}
}

// ------------------------------------------
/**
 Create a dispatch queue name based on the current application bundle
 */
fileprivate func createAsyncDispatchQueueName()
{
    fileprivate let appName = Bundle.main.displayName
    fileprivate let gcdQueueBaseName = appName ?? "app.\(arc4random())"
    
    return gcdQueueBaseName + ".concurrentQueue"
}

/// Name of the private dispatch queue used by the global `async(afterSeconds:)` function.
fileprivate let concurrentQueueName = createAsyncDispatchQueueName()

/// Private dispatch queue used by the global `async(afterSeconds:)` function.
fileprivate let _concurrentQueue = DispatchQueue(
	label: concurrentQueueName,
	attributes: .concurrent
)

// MARK:- Dispatch Queue Extension
// ------------------------------------------
public extension DispatchQueue
{
    /// Private dispatch queue used by the global `async(afterSeconds:)` function.
	fileprivate static var concurrentQueue: DispatchQueue {
        return _concurrentQueue
    }
	
    // ------------------------------------------
    /**
     Execute a closure asynchronously on this `DispatchQueue`, returning a `Future`
     
     - Parameters:
        - delay: Number of seconds to delay executing `executionBlock`, or `nil` for no delay.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
        by it.
     */
	func async<T>(
		afterSeconds delay:Double? = nil,
		_ executionBlock:@escaping () throws -> T) -> Future<T>
	{
		let promise = Promise<T>()
		
		if let delaySeconds = delay
		{
			self.asyncAfter(
				deadline: .now() + delaySeconds,
				qos: .userInitiated,
				flags: .detached)
			{
				do { promise.set(value: try executionBlock()) }
				catch let err {
					promise.set(error: err)
				}
			}
		}
		else
		{
			self.async(group: nil, qos: .userInitiated, flags: .detached)
			{
				do { promise.set(value: try executionBlock()) }
				catch let err {
					promise.set(error: err)
				}
			}
		}

		return promise.future
	}

    // ------------------------------------------
    /**
     Execute a closure synchronously on this `DispatchQueue`, returning a `Future`
     
     - Parameters:
        - delay: Number of seconds to delay executing `executionBlock`, or `nil` for no delay.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
        by it.
     */
	func sync<T>(
		afterSeconds delay:Double? = nil,
		_ executionBlock:@escaping () throws -> T) -> Future<T>
	{
		return DispatchQueue.sync(afterSeconds: delay, executionBlock)
	}
	
    // ------------------------------------------
    /**
     Execute a closure synchronously, returning a `Future`
     
     - Parameters:
        - delay: Number of seconds to delay executing `executionBlock`, or `nil` for no delay.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown
        by it.
     */
	static func sync<T>(
		afterSeconds delay:Double? = nil,
		_ executionBlock:@escaping () throws -> T) -> Future<T>
	{
		if let delaySeconds = delay {
			sleep(forSeconds: delaySeconds)
		}
		
		let promise = Promise<T>()
		
		do { promise.set(value: try executionBlock()) }
		catch let err {
			promise.set(error: err)
		}

		return promise.future
	}

	// ------------------------------------------
	/**
	Blocks this thread for at least the specified number of seconds.  Actual
	blocking time might be more than the specified time.  If this thread
	receives a signal, `sleep` will return early with a POSIX error number.
	
	*See slso:* [POSIX.1 `nanosleep`](https://www.unix.com/man-page/POSIX/3posix/nanosleep/)
	- SeeAlso: [POSIX.1 `nanosleep`](https://www.unix.com/man-page/POSIX/3posix/nanosleep/)
	
	- Parameter forSeconds: Time to sleep expressed in seconds.  May be
		fractional.  If non-positive, `sleep` returns immediately.
	
	- Returns: nil on success, or a `UInt32` representing the C/POSIX.1 `errno`
		set by the underlying call to `nanosleep`, which indicates that this
		thread received a signal.  If the `forSeconds` parameter is negative,
		`EINVAL` is immediately returned.
	*/
	@discardableResult
	private static func sleep(forSeconds: Double) -> Int32?
	{
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(Linux)
		assert(forSeconds >= 0)
		
		guard forSeconds > 0 else {
			return forSeconds == 0 ? nil : EINVAL
		}
		
		let oneBillion = 1.0e+9
		let wholeSeconds = Int(forSeconds)
		let nanoseconds = Int((forSeconds - Double(wholeSeconds)) * oneBillion)

		var t = timespec(tv_sec: wholeSeconds, tv_nsec: nanoseconds)
		return withUnsafePointer(to: &t)
		{
			(ts) -> Int32? in
			if nanosleep(ts, nil) != 0 {
				return errno
			}
			return nil
		}
        #elseif os("Windows")
            #error("Implement a Windows version of sleep!")
        #else
            /*
             If your target platform is a POSIX system, you can include it above
             with all the Apple OSes and Linux.  Otherwise you will need to add
             your own #elseif case for it and implement sleep there.
             */
            #error("Implement a version of sleep for your platform!")
        #endif
	}
}

// MARK:- Aysnc Control
// ------------------------------------------
/**
 Allows automatically deciding to run an async task synchronously, if the current number of simultaneously
 running tasks run by the global `async(afterSeconds:)` function exceeds according to the number of
 cores on the current machine, with any further submitted tasks being run synchronously until a currently
 running asynchronous task is completes.
 */
fileprivate struct AsyncControl
{
    /**
     If `true`, `AsyncControl` will limit the number of tasks that are run asynchronously by the global `async(afterSeconds:)` function.  If `false`, that function will always run tasks asynchronously.
     */
    static let limitAsyncByCores = true
    
    /**
     If limitAsyncByCores is `true`, the global `async(afterSeconds:)` function will limit the number
     currently running asynchronous tasks to the number of cores on the current system times this factor.
     */
    static let coreLimitFactor = 2
    
    /// Number of CPU cores on the current system.
    static let numCores = ProcessInfo.processInfo.processorCount * 2
    
    /**
     If the number of currently running asynchronous tasks run by the global `async(afterSeconds:)`
     function  exceeds this `asyncLimit`, a new task being submitted will be run synchronously.
     `asyncLimit` is less than 0, then all requsted tasks are run asynchronously.
     */
	static let asyncLimit = 2 * numCores
    
    /// Number of currently running asynchronous tasks submitted started by `async(afterSeconds:)`
	static var asyncCount = 0
    
    /// A mutex lock to guard `asyncCount`, which must be updated as tasks start and complete.
	static var mutex = Mutex()
    
    /**
     DispatchQueue on which to execute tasks submitted to the global `async(afterSeconds:)`
     function
     */
	static let concurrentQueue = DispatchQueue.concurrentQueue
	
	// ------------------------------------------
    /// `true` if the currently requested task should be run asynchronously, `false` otherwise.
	private static var runAsAsync: Bool
	{
		return mutex.protect
		{
            guard limitAsyncByCores else { return true }
			
			if asyncCount < asyncLimit
			{
                mutex.protect { asyncCount += 1 }
				return true
			}
			return false
		}
	}
	
	// ------------------------------------------
    /**
     Execute a closure asynchronously if the current number of asynchronous tasks is less than
     `asyncLimit` or if `limitAsyncByCores` is `false`; otherwise, run it synchronously
     
     - Parameters:
        - delay: Number of seconds to delay executing `executionBlock`, or `nil` for no delay.
        - executionBlock: The closure to be executed
     
     - Returns: a `Future` for the value returned by the closure.
     */
	static func async<T>(
		afterSeconds delay:Double? = nil,
		_ executionBlock:@escaping () throws -> T) -> Future<T>
	{
		if runAsAsync
		{
			return concurrentQueue.async(afterSeconds: delay)
			{
				() -> T in
				
				defer { mutex.protect { asyncCount -= 1 } }
				return try executionBlock()
			}
		}
		else {
			return concurrentQueue.sync { return try executionBlock() }
		}
	}
}

// ------------------------------------------
/**
 Execute a closure asynchronously on a default asynchronous queue, if the number of currently scheduled
 tasks do not exceed a limit based on the number of available cores, otherwise the task is run synchronously.
 
 If `excecutionBlock` throws, the returned `Future`'s `value` property will be `nil`, and its
 `error` property will contain the thrown `error`.
 
 Using this method has two advantages:
 
    - It returns a `Future` making asynchronous tasks easiser
    - It prevents flooding Grand Central Dispatch with asynchronous which can degrade its performance.
 
 - Note: This `Async` module provides an exenstion on `DispatchQueue` containing an instance
 method that allows you to execute a closure on a `DispatchQueue` you specify without regard to the
 number of cores on the system.  That method allows you to take advantage of returning a `Future` while
 by-passing the CPU limit imposed by this function, and of course, you can use it on any `DispatchQueue`
 you wish, where as this one is a convenience that runs on a privately defined queue
 
 - Parameters:
    - delay: Number of seconds to delay executing `executionBlock`, or `nil` for no delay.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown by it.
 */
public func async<T>(
	afterSeconds delay:Double? = nil,
	_ executionBlock:@escaping () throws -> T) -> Future<T>
{
	return AsyncControl.async(afterSeconds: delay, executionBlock)
}

// ------------------------------------------
/**
 Execute a closure synchronously.
 
 This function is provided to allow easily switching from `async` and `sync` while debugging.
 
 - Parameters:
    - delay: Number of seconds to delay executing `executionBlock`, or `nil` for no delay.
    - executionBlock: The closure to be executed
 
 - Returns: a `Future` containing either the value returned by the closure, or an `Error` thrown by it.
 */
public func sync<T>(
	afterSeconds delay:Double? = nil,
	_ executionBlock:@escaping () throws -> T) -> Future<T>
{
	return DispatchQueue.sync(afterSeconds: delay, executionBlock)
}

