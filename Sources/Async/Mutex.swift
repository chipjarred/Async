//
//  Mutex.swift
//  FuzzyBTC2
//
//  Created by Chip Jarred on 1/16/18.
//  Copyright © 2018 Chip Jarred. All rights reserved.
//

import Foundation

// ------------------------------------------
public class Mutex
{
	private var semaphore = DispatchSemaphore(value: 1)
	private var countSemaphore = DispatchSemaphore(value: 1)
	private var lockCount = 0
	
	// ------------------------------------------
	public var isLocked:Bool
	{
		countSemaphore.wait()
		defer { countSemaphore.signal() }
		
		return lockCount > 0
	}
	
	// ------------------------------------------
	public init() {
	}
	
	// ------------------------------------------
	deinit {
		unlock(checkUnbalanced: false)
	}
	
	// ------------------------------------------
	public func lock()
	{
		countSemaphore.wait()
		assert(lockCount >= 0)
		lockCount += 1
		countSemaphore.signal()
		
		semaphore.wait()
	}
	
	// ------------------------------------------
	public func unlock() {
		unlock(checkUnbalanced: true)
	}
	
	// ------------------------------------------
	private func unlock(checkUnbalanced:Bool)
	{
		countSemaphore.wait()
		assert(lockCount > 0 || !checkUnbalanced, "All locks already balanced by unlocks (lockCount = \(lockCount))")
		if lockCount > 0
		{
			lockCount -= 1
			countSemaphore.signal()
			
			semaphore.signal()
		}
		else {
			countSemaphore.signal()
		}
	}
	
	// ------------------------------------------
	/**
	Protect a critical execution block by locking this mutex during its
	execution.  This mutex is unlocked on return.
	*/
	public func protect<T>(_ executionBlock:@escaping () -> T) -> T
	{
		self.lock()
		defer { self.unlock() }
		return executionBlock()
	}
	
	// ------------------------------------------
	/**
	Protect a critical execution block by locking this mutex during its
	execution.  This mutex is unlocked on return.
	*/
	public func protect(_ executionBlock:@escaping () -> Void)
	{
		self.lock()
		defer { self.unlock() }
		executionBlock()
	}
	
	// ------------------------------------------
	/**
	Protect a critical execution block by locking this mutex during its
	execution.  This mutex is unlocked on return or when an exception is thrown.
	*/
	public func protect<T>(_ executionBlock:@escaping () throws -> T) throws -> T
	{
		self.lock()
		defer { self.unlock() }
		return try executionBlock()
	}
	
	// ------------------------------------------
	/**
	Protect a critical execution block by locking this mutex during its
	execution.  This mutex is unlocked on return or when an exception is thrown.
	*/
	public func protect(_ executionBlock:@escaping () throws -> Void) throws
	{
		self.lock()
		defer { self.unlock() }
		try executionBlock()
	}
}
