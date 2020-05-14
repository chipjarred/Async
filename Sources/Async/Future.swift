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

public enum FutureError: Error { case timeOut }

// ------------------------------------------
/**
 `Future` is the consumer part of a `Promise`/`Future` pair.   It receives the result of a closure called
 within a `Promise`, normally in an asynchronous context.
 
 A `Future` can be viewed as a place-holder for a value to be provided by a parallel task in the future.  It
 can also be viewed as the receiver end of a  thread-safe single-value communication channel, for which a
 corresponding `Promise` is the sender.  The result received can be either a value returned by the closure
 called within a `Promise`, or an error thrown by it.
 
 A `Future` cannot be created directly, but rather one is obtained ultimately from a `Promise`.  The
 various `sync` and `async` functions and methods of this `Async` package return `Future`s.  If you
 need to produce a `Future` yourself, see the documenation for `Promise`.
 
 There are two main styles of `Future`s in the industry: functional and imperative.   This implementation
 supports both.
 
 In the functional style, found in JavaScript, for example, success and failure handlers are specified to be
 called asynchronously.  In this case, the `Future` itself generally doesn't appear at the call site source
 code, because it disappears behind fluid syntax:
 
        async { /* some long-running task */ }
            .onSuccess { value in
                /*
                 code to handle value if the the long-running
                 task succeeds
                 */
 
            }
            .onFailure { error in
                /*
                 code to handle an error thrown by the
                 long-running task
                 */
            }
 
 Of course the `Future` is there in the temporary values between method calls.  We can expose it by
 assigning the result of `async` to a variable and then set our handlers.
 
        let future = async { /* some long-running task */ }
 
        future.onSuccess { value in
            /*
             code to handle value if the the long-running
             task succeeds
             */
 
        }
 
        future.onFailure { error in
            /*
             code to handle an error thrown by the
             long-running task
             */
        }
 
 If you prefer to use Swift's `Result` type, you can specify a more general completion handler:
 
           async { /* some long-running task */ }
               .onCompletion {
                    switch $0 {
                        case let .success(value):
                            // code to handle value
                        case let .failure(error):
                            // code to handle an error
                    }
               }
 
 You can specify as many handlers as you like, including none at all, as well as mix success handlers, failure
 handlers, and completion handlers.  All applicable handlers will be run when the promise sets either a value
 or an error.  Behind the scenes completion handlers are registered as both success and failure handlers with
 a thin wrapper closure to convert the value or error into a `Result`.
 
 The imperative style, found in C++'s std::future, is treated like any function return value.  It is typically stored
 in a named variable, and then it's value/error are accessed from that variable.  In this case, the future
 becomes more explicit.
 
        let future = async { /* some long-running task */ }
 
        /* continue doing some work and then ... */
 
        guard let value = future.value else {
            let error = future.error!
        }
 
        /* do something with value */
 
 This imperative style also supporst working with Swift's `Result` type:
 
        let future = async { /* some long-running task */ }
 
        /* continue doing some work and then ... */
 
        switch future.result {
            case let .success(value):
                // code to handle value
 
            case let .failure(error):
                // code to handle an error
        }
 
 If you prefer to catch a possible error from the `Future` rather than explicitly extract it, you can use the
 throwing `getValue()` method:
 
        let future = async { /* some long-running task */ }
 
        /* continue doing some work and then ... */
 
        do {
            let value = try future.getValue()
 
            // handle the value
        }
        catch {
            // handle the error
        }

 
 If the `Promise` on the other end of the connection has not yet set the `Future` yet, accessing the
 `value`, `error`, or `result` property will block until it is set, as will calling the `getValue()`
 method; therefore, it is useful to be able to test whether the `Future` has been set.  For that purpose, it
 provides a non-blocking `isReady` property that returns `true` if either a value or error has been set, and
 `false`, if not.  It also provides non-blocking `hasValue` and `hasError` properties that return
 `true` if the `Future` is ready and it has the corresponding result.
 
 If you simply need to wait for the asynchronous task to complete before continuing, as might be the case
 if the task is a void function for which you need to synchronize at some point, then you can call the `wait`
 method (and of course, it blocks until the `Future` is ready):
 
       let future = async { /* some long-running task */ }

       /* continue doing some work and then ... */

       future.wait()
 
 Although the functional style is preferred by many, and has the advantage that the code spawning the
 asynchronous task  never blocks,  imperative usage has some of advantages.  It allows you to store the future
 in a collection.  There can be any number of usages for this, but one common one is when you split a task into
 a number of smaller tasks, and must, regardless of programming style wait on the result before continuing:
 
        var futures = [Future<()>]()
 
        // process the members of items in parallel
        for item in items {
            futures.append(
                async {
                    process(item)
                }
            )
        }
 
        // Now wait for the all the tasks to complete
        for future in futures { future.wait() }
 
 Of course the imperative interface of `Future` can be combined nicely with a functional style
 
        items.map { async { process($0) } }.map { $0.wait() }
 
 Another advantage of the imperative interface is that you can extending `Future` for specific wrapped
 types, you can create a poor-mans parallel computuation graph on the fly.
 */
public final class Future<T>
{
    public typealias ValueHandler = (_:T) -> Void
    public typealias ErrorHandler = (_:Error) -> Void
    public typealias CompletionHandler = (_: Result<T, Error>) -> Void
    
    private var resultLock = Mutex()
    private var _value:T? = nil
    private var _error:Error? = nil
    
    private var handlerLock = Mutex()
    private var _valueHandlers = [ValueHandler]()
    private var _errorHandlers = [ErrorHandler]()
    
    private var timeoutLock = Mutex()

    // ------------------------------------------
    /// Determine if this `Future` has set either a value or  error without blocking
    public final var isReady: Bool { return hasValue || hasError }
    
    /// Determine if this `Future` has a value yet, without blocking.  Does not check if there is an error
    public final var hasValue: Bool { return _value != nil }
    
    /// Determine if this `Future` has an error yet, without blocking.  Does not check if there is a value.
    public final var hasError: Bool { return _error != nil }
    
    // ------------------------------------------
    /**
     Value set by the corresponding `Promise`, or `()` if `T` is `Void`.  If `nil`, the `error`
     property will contain an error.
     
     - Important: accessing this property will block until either a value or error is set by the `Promise`
     */
    public final var value:T?
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
    public final var error: Error?
    {
        wait()
        return _error
    }
    
    // ------------------------------------------
    /**
     Obtain a `Result` set by the `Promise`.
     
     - Important: accessing this property will block until either a value or error is set by the `Promise`
     */
    public final var result: Result<T, Error>
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
    public final func getValue() throws -> T
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
    public final func wait()
    {
        lock()
        unlock()
    }
    
    // ------------------------------------------
    /**
     Wait up to the specified deadline for this `Future` to be ready, which is to say wait until it has either a
     value or an error.
     
     - Parameter deadline: `DispatchTime` after which this `wait` should time-out if neither a
        value nor error is set before.
     
     - Returns: `.success` if the `Future` was set before the specified deadline, or .timedOut if the
        deadline was reached first.
     
     - Important: Unlike the `timeout` methods, this method does not prevent the corresponding
        `Promise` from subsequently setting this `Future`'s value or error.
     */
    public final func wait(
        until deadline: DispatchTime) -> DispatchTimeoutResult
    {
        let result = tryLock(deadline: deadline)
        if result == .success { unlock() }
        return result
    }
    
    // ------------------------------------------
    /**
     Wait up to the specified timeout for this `Future` to be ready, which is to say wait until it has either a
     value or an error.
     
     - Parameter timeout: `DispatchTimeInterval` to wait for this `Future` to be set

     - Returns: `.success` if the `Future` was set before the specified deadline, or .timedOut if the
        deadline was reached first.
     
     - Important: Unlike the `timeout` methods, this method does not prevent the corresponding
        `Promise` from subsequently setting this `Future`'s value or error.
     */
    @inlinable
    public final func wait(
        timeout: DispatchTimeInterval) -> DispatchTimeoutResult
    {
        return wait(until: .now() + timeout)
    }
    
    // ------------------------------------------
    /**
     Wait up to the specied seconds for this `Future` to be ready, which is to say wait until it has either a
     value or an error.
     
     - Parameter seconds: Seconds to wait for this `Future` to be set

     - Returns: `.success` if the `Future` was set before the specified deadline, or .timedOut if the
        deadline was reached first.
     
     - Important: Unlike the `timeout` methods, this method does not prevent the corresponding
        `Promise` from subsequently setting this `Future`'s value or error.
     */
    @inlinable
    public final func wait(
        seconds: TimeInterval) -> DispatchTimeoutResult
    {
        return wait(
            timeout: DispatchTimeInterval.nanoseconds(Int(seconds * 1_e+9))
        )
    }

    // ------------------------------------------
    /**
     Add a closure to run when this `Future` has a value.
     
     - Parameter handler: closure to run when the corresponding `Promise` sets a value in this
        `Future.`
     
     - Returns: This `Future` allowing chaining in a functional/fluid style
     */
    @discardableResult
    public final func onSuccess(do handler: @escaping ValueHandler) -> Self
    {
        handlerLock.withLock
        {
            if self.hasValue {
                handler(self.value!)
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

     - Parameter handler: closure to run when the corresponding `Promise` sets an error  in this
        `Future.`
     
     - Returns: This `Future` allowing chaining in a functional/fluid style
     */
    @discardableResult
    public final func onFailure(do handler: @escaping ErrorHandler) -> Self
    {
        handlerLock.withLock
        {
            if self.hasError {
                handler(self._error!)
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
     
     - Parameter handler: closure to run when the corresponding `Promise` sets either a value or
        an error  in this `Future.`
     
     - Returns: This `Future` allowing chaining in a functional/fluid style
     */
    @discardableResult
    public final func onCompletion(do handler: @escaping CompletionHandler) -> Self
    {
        handlerLock.withLock
        {
            if self.isReady {
                handler(self.result)
            }
            else
            {
                self._valueHandlers.append { handler(.success($0)) }
                self._errorHandlers.append { handler(.failure($0)) }
            }
        }
        
        return self
    }
        
    // ------------------------------------------
    /**
     Specify a time-out for this `Future`.
     
     If the deadline is reached before a value or error is set, a `FutureError.timeOut` error is set.
    
     - Parameter deadline: `DispatchTime` after which this `Future` should time-out.
     
     - Important: If the time-out set in this method is triggered, the corresponding `Promise` is
        prevented from subsequently setting a value or error.  If you wish time-out behavior that still allows
        for subsequent setting of this `Future`, use the blocking `wait(timeout:)` method.
     */
    @discardableResult
    public final func timeout(deadline: DispatchTime) -> Self
    {
        let _ = futureHandlerQueue.async(afterDeadline: deadline) {
            self.set(error: FutureError.timeOut)
        }
        
        return self
    }
    
    // ------------------------------------------
    /**
     Specify a time-out for this `Future`.
     
     If the deadline is reached before a value or error is set, a `FutureError.timeOut` error is set.
    
     - Parameter delay: `DispatchTimeInterval` from now  that this `Future` should time-out.
     
     - Important: If the time-out set in this method is triggered, the corresponding `Promise` is
        prevented from subsequently setting a value or error.  If you wish time-out behavior that still allows
        for subsequent setting of this `Future`, use the blocking `wait(timeout:)` method.
     */
    @discardableResult
    @inlinable
    public final func timeout(interval delay: DispatchTimeInterval) -> Self {
        return timeout(deadline: .now() + delay)
    }
    
    // ------------------------------------------
    /**
     Specify a time-out for this `Future`.
     
     If the deadline is reached before a value or error is set, a `FutureError.timeOut` error is set.
    
     - Parameter delay: Seconds from now when  this `Future` should time-out.
     
     - Important: If the time-out set in this method is triggered, the corresponding `Promise` is
        prevented from subsequently setting a value or error.  If you wish time-out behavior that still allows
        for subsequent setting of this `Future`, use the blocking `wait(timeout:)` method.
     */
    @discardableResult
    @inlinable
    public final func timeout(delay: TimeInterval) -> Self {
        return timeout(interval: .nanoseconds(Int(delay * 1_e+9)))
    }

    // ------------------------------------------
    /// Used by `Promise` to set the value for this `Future`
    internal final func set(value:T)
    {
        let runHandlers: Bool = timeoutLock.withLock
        {
            // We might have timed-out so can't assume we can set anything
            guard _error == nil else { return false }
            
            assert(_value == nil)
            
            _value = value
            unlock()
            return true
        }
        
        if runHandlers {
            handlerLock.withLock { callValueHandlers() }
        }
    }
    
    // ------------------------------------------
    /// Used by `Promise` to set the error for this `Future`
    internal final func set(error: Error)
    {
        let runHandlers: Bool = timeoutLock.withLock
        {
            // We might have timed-out so can't assume we can set anything
            guard _error == nil && _value == nil  else { return false }
            
            _error = error
            unlock()
            
            return true
        }
        
        if runHandlers {
            handlerLock.withLock { callErrorHandlers() }
        }
    }
    
    // ------------------------------------------
    private func lock() {
        resultLock.lock()
    }
    
    // ------------------------------------------
    private func tryLock(deadline: DispatchTime) -> DispatchTimeoutResult {
        return resultLock.tryLock(deadline: deadline) ? .success : .timedOut
    }

    // ------------------------------------------
    private func unlock() {
        resultLock.unlock()
    }
    
    // ------------------------------------------
    private func callValueHandlers()
    {
        assert(hasValue)
        
        _valueHandlers.forEach
        {
            handler in
            let _ = futureHandlerQueue.async {
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
            let _ = futureHandlerQueue.async {
                handler(self._error!)
            }
        }
    }
}
