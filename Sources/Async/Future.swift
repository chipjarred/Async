//
//  Future.swift
//  FuzzyBTC2
//
//  Created by Chip Jarred on 1/16/18.
//  Copyright © 2018 Chip Jarred. All rights reserved.
//

import Foundation

// ------------------------------------------
public class Future<T>
{
	public typealias ValueHandler = (_:T) -> Void
	public typealias ErrorHandler = (_:Error) -> Void
	public typealias CompletionHandler = (_: Result<T, Error>) -> Void
	
	private var semaphore = DispatchSemaphore(value: 1)
	private var _value:T? = nil
	private var _error:Error? = nil
	
	private var handlerLock = LockGuard()
	private var _valueHandlers = [ValueHandler]()
	private var _errorHandlers = [ErrorHandler]()
	private var _completionHandlers = [CompletionHandler]()

	// ------------------------------------------
    /// Determine if this `Future` has set either a value or  error without blocking
	public var isReady: Bool { return hasValue || hasError }
    
    /// Determine if this `Future` has a value yet, without blocking.  Does not check if there is an error
	public var hasValue: Bool { return _value != nil }
    
    /// Determine if this `Future` has an error yet, without blocking.  Does not check if there is a value.
	public var hasError: Bool { return _error != nil }
	
	// ------------------------------------------
    /**
     Value set by the corresponding `Promise`, or `()` if `T` is `Void`.  If `nil`, the `error`
     property will contain an error.
     
     - Important: accessing this property will block until either a value or error is set by the `Promise`
     */
	public var value:T?
	{
		do {
			return try getValue()
		}
		catch {
			return nil
		}
	}
	
    // ------------------------------------------
    /**
     `Error` set by the corresponding `Promise`.  If `nil`, no error was set, and value will contain the
     returned value.
     
     - Important: accessing this property will block until either a value or error is set by the `Promise`
     */
	public var error: Error?
	{
		wait()
		return _error
	}
	
	// ------------------------------------------
	public var result: Result<T, Error>
	{
		wait()
		
        if self.hasError { return .failure(_error!) }
        
        assert(self.hasValue)
        return .success(_value!)
	}
	
	// ------------------------------------------
	internal init() {
		self.lock()
	}
	
    // ------------------------------------------
    /**
     Get the value set by the corresponding `Promise`, or throw any `Error` it may have set.
     
     This method allows handling the `Error` with `do...catch`, if that makes more sense for your
     code.
     
     - Returns: The value set by the `Promise`.
     - Throws: Throws whaver `Error` is set by the corresponding `Promise`
     
     - Important: this function will block until either a value or error is set by the `Promise`
     */
	public func getValue() throws -> T
	{
		wait()

		if hasError {
			throw _error!
		}
		
		assert(hasValue)
		
		return _value!
	}
	
	// ------------------------------------------
    /**
     Wait for this `Future` to be ready, which is to say wait until it has either a value or an error.
     */
	public func wait()
	{
		lock()
		do { unlock() }
	}
	
	// ------------------------------------------
    /**
     Add a closure to run when this `Future` has a value.
     
     Value handlers are run in the order they are added before completion handlers.
     
     - Parameter handler: closure to run when the corresponding `Promise` sets a value in this
        `Future.`
     
     - Returns: This `Future` allowing chaining in a functional/fluid style
     */
    @discardableResult
	public func withValue(do handler: @escaping ValueHandler) -> Self
	{
		handlerLock.withLock
		{
			if self.hasValue {
				let _ = async { handler(self.value!) }
			}
			else {
				self._valueHandlers.append(handler)
			}
		}
        
        return self
	}
	
	// ------------------------------------------
    /**
     Add a closure to run when this `Future` has an error set
     
     Error handlers are run in the order they are added before completion handlers.

     - Parameter handler: closure to run when the corresponding `Promise` sets an error  in this
        `Future.`
     
     - Returns: This `Future` allowing chaining in a functional/fluid style
     */
    @discardableResult
	public func onError(do handler: @escaping ErrorHandler) -> Self
	{
		handlerLock.withLock
		{
			if self.hasError {
				let _ = async { handler(self._error!) }
			}
			else {
				self._errorHandlers.append(handler)
			}
		}
        return self
	}
    
    // ------------------------------------------
    /**
     Set a closure to run when this `Future` has either a value or error set
     
     Completion handlers are run in the order they are added, but after value or error handlers have been run.

     - Parameter handler: closure to run when the corresponding `Promise` sets either a value or
        an error  in this `Future.`
     
     - Returns: This `Future` allowing chaining in a functional/fluid style
     */
    @discardableResult
	public func onCompletion(do handler: @escaping CompletionHandler) -> Self
	{
		handlerLock.withLock
		{
			if self.isReady {
				let _ = async { handler(self.result) }
			}
			else {
				self._completionHandlers.append(handler)
			}
		}
        
        return self
	}
	
	// ------------------------------------------
	internal func set(value:T)
	{
		assert(_value == nil)
		
		_value = value
		unlock()
		
		handlerLock.withLock
		{
			callValueHandlers()
			callCompletionHandlers()
		}
	}
	
	// ------------------------------------------
	internal func set(error: Error)
	{
		assert(_error == nil)
		_error = error
		unlock()
		
		handlerLock.withLock
		{
			callErrorHandlers()
			callCompletionHandlers()
		}
	}
	
	// ------------------------------------------
	private func lock() {
		semaphore.wait()
	}
	
	// ------------------------------------------
	private func unlock() {
		semaphore.signal()
	}
	
	// ------------------------------------------
	private func callValueHandlers()
	{
		assert(hasValue)
		
		_valueHandlers.forEach
		{
			handler in
			let _ = async {
				handler(self._value!)
			}
		}
	}
	
	// ------------------------------------------
	private func callErrorHandlers()
	{
		assert(hasError)
		
		_errorHandlers.forEach
		{
			handler in
			let _ = async {
				handler(self._error!)
			}
		}
	}
	
	// ------------------------------------------
	private func callCompletionHandlers()
	{
		assert(isReady)
		
		_completionHandlers.forEach
		{
			handler in
			let _ = async {
				handler(self.result)
			}
		}
	}
}
