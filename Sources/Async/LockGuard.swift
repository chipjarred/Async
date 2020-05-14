//
//  LockGuard.swift
//  Async
//
//  Created by Chip Jarred on 2/24/19.
//  Copyright © 2019 Chip Jarred. All rights reserved.
//

import Foundation

// ----------------------------------
public struct LockGuard
{
	public var semaphore: DispatchSemaphore

	// ----------------------------------
	@inlinable
	public init(initiallyLocked: Bool = false)
	{
		self.semaphore = DispatchSemaphore(value: 1)
		if initiallyLocked {
			lock()
		}
	}
	
	// ----------------------------------
	@inlinable
	public func withLock<R>(execute: () throws -> R) rethrows -> R
	{
		lock()
		defer { unlock() }
		
		return try execute()
	}
	
	// ----------------------------------
	@inlinable
	public func tryLock() -> Bool {
		return semaphore.wait(timeout: .now()) == .success
	}

	// ----------------------------------
	@inlinable
	public func lock() {
		_ = semaphore.wait(timeout: DispatchTime.distantFuture)
	}
	
	// ----------------------------------
	@inlinable
	public func unlock() {
		semaphore.signal()
	}
}

// ----------------------------------
public struct NoOpLockGuard
{
	// ----------------------------------
	@inlinable
	public init(initiallyLocked: Bool = false) { }
	
	// ----------------------------------
	@inlinable
	public func withLock<R>(execute: () throws -> R) rethrows -> R {
		return try execute()
	}
	
	// ----------------------------------
	@inlinable
	public func tryLock() -> Bool { return true }
	
	// ----------------------------------
	@inlinable
	public func lock() { }
	
	// ----------------------------------
	@inlinable
	public func unlock() { }
}
