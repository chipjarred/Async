// Copyright 2020 Chip Jarred
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
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
 `Promise` is the confusingly named  "provider" half of a `Promise`/`Future` pair. (see the note at the
 end for why it's confusing).  It is the only way to create a `Future` ,  and it is what sets a value or error in
 the `Future` it creates.  Put another way, it is the sender side of a single value communication channel for
 asynchronous code, whereas  a `Future` is the receiver side of that channel.
 
 You usually will not need to create a `Promise` yourself, since the `async` functions and methods of this
 `Async` package use it internally to return a `Future` to your code immediately;  however, doing so is
 simple and useful for customizing your own asynchronous dispatch.
 
 The three steps to using a `Promise` to return a `Future` illustrated by the follwing example.
 Suppose you want to use `DispatchQueue`'s native `async` method to run some arbitrary code
 asynchronousely in the `main` `DispatchQueue` and immediately return a `Future` for the eventual
 result of that code:
 
        func dispatchInMainQueue<R>(
            code: () throws -> R) -> Future<R>
        {
            // Step 1: Create the promise prior to dispatch
            let promise = Promise()
     
            // Step 2: In a dispatched closure of your own, pass
            //   the caller-supplied closure to the promise's
            //   setResult(from:) method
            DispatchQueue.main.async {
                promise.set(from: code)
            }
     
            // Step 3: Return the Promise's future property.
            return promise.future
        }
 
 That's all there is to it.  At some point later, when GCD gets around to running the asynchronous code, the
 `Promise` captures any value returned or error thrown by the closure passed to its `setResult` method,
 and sets those in its `Future` to communicate the results to the client code holding the `Future` that was
 immediately returned.  If the caller used a functional style, setting a completion closure, that closure will be
 called at this time.  If on the other hand, they chose a more imperative style, the value or error is made
 available in the `Future`, and if the caller is currently blocked waiting on those results, it will be awakened.
 
 - Note: Though it is the accepted industry term for what it does, "`Promise`" is a confusing name.  In
 ordinary English, if Alice promises to give Bob $10 at some later date, what she immediately gives to Bob is
 her promise, and what she retains is an "obligation."  Yet in asynchronouse programming, what the dispatching
 code gives the caller is a "future" and what it retains is a "promise".   If we were naming these things from
 scratch, what we currently call a "future" should be called a "promise" (or "IOU"), and what we currently call a
 "promise" should be called an "obligation."
 
 "Future"  isn't a terrible name for what Bob has, and is consistent with commodity markets usage (though
 more formally those are "future contracts").  It indicates that it's a placeholder for something to be
 obtained in the future, so it's a reasonable name.  But "promise" is definitely not what Alice retains.
 
 In any case, if we ever get around renaming these things as a community, we should consider ditching the
 word "Promise" in this context altogether, replacing it with "Obligation".
 */
public struct Promise<T>
{
    /// `Future` through which the results of code used to set values with this `Promise` can be read.
	public let future:Future<T>
	
	// ------------------------------------------
    // Create a `Promise`.
	public init() { self.future = Future<T>() }
    
    // ------------------------------------------
    /**
     Call the specifed closure, setting the returned value or thrown error in this `Promise`'s `Future`
     
     - Parameter code: closure from which to obtain the value or error to set in the `Future`
     */
    public func set(from code: () throws -> T)
    {
        do { future.set(value: try code()) }
        catch { future.set(error: error) }
    }
    
    // ------------------------------------------
    /**
     Call the specifed closure that returns a `Result` and set this `Promise`'s `Future` according to
     that `Result`
     
     - Parameter code: closure from which to obtain the `Result` to set in the `Future`
     */
    public func setResult(from code: () -> Result<T, Error>)
    {
        switch code()
        {
            case let .success(value) : future.set(value: value)
            case let .failure(error) : future.set(error: error)
        }
    }
}
