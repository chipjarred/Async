#  Async

`Async` is a framework of functions and types that I have found incredibly useful in working with *Grand Central Dispatch*, although the work horses of the library, `Future` and its coresponding `Promise`,  are useful in a wider variety of contexts.   I've been using these in my own code for a long time, and have always meant to share them, so now I finally am.   I have other types and functions I have found useful that I may add later, but these form the core functionality I use nearly every time I use GCD.  

Even though `Future` is really the central feature, the library is called `Async` because it provides global `async` free functions and adds coresponding methods on `DispatchQueue` that return a `Future`, so I almost never need to explictly create a `Promise` , and often the `Future` itself just disappears behind fluid completion handler syntax, so that it almost seems as though the library is about `async`.   But actually `Future` is the hero, and it's more flexible than most `Future` implementations I've seen.

I often try an idea by using writing a command line tool rather than an actual AppKit/UIKit application, so this package is specifically designed to be independent of those.  It uses only GCD and Foundation.

## What's Included

### async

There are a  few variations of a global  `async` free function that immediately return a `Future`, asynchronously executing your closure, which can safely throw an error, on a global default concurrent `DispatchQueue`. You don't need to create a queue explictly yourself, unless you just need it for some other reason.  

I provide a few variations, because I find it annoying that it's necessary to specify a deadline in GCD's `asyncAfter` as a `DispatchTime`.  I almost always want my code to run either as soon as possible or after a specified delay from the moment I called `async`, and nearly never need it to run at a specific point in time.  So I provide variations on my `async` function that allow you specify a deadline as a `DispatchTime`, as with GCD's native version, or a delay as `DispatchTimeInterval` or `TimeInterval`.

### sync

There are *synchronous* versons of the global  `async` free functions.  They merely run your closure immediately in the current thread as though you had called it directly yourself.  This is useful for several reasons:
        
• It allows an intermediate step in refactoring synchronous code into asynchronous during which you are still executing a code synchronously while getting a `Future` from it.  In that case, the `Future` is ready immediately when your closure returns, and if you added handlers, they are called immediately.   Then by simply changing `sync` to `async`, it becomes truly asynchronous.   

• It is sometimes helpful for debugging to use `sync`  instead of `async` temporarily, and it is a simple one-letter code change.   

• It returns a `Future`, so you can use it inside of your own code as an easy way to return a `Future` without worrying about how to use `Promise`, although `Promise` is pretty easy to use directly.


### DispatchQueue extension

`async` and `sync` methods have been added to `DispatchQueue` to corespond to their global versions, but allow you get the `Future` returning behavior on the queue of your choice instead of the default global concurrent queue.

### Mutex

`Mutex` is a class that simplifies guarding shared data for thread safety by providing a `withLock` method to automate locking and unlocking the mutex, which is what should be used most of the time; however,  recognizing that sometimes it's necesary to interleave locking and unlocking different mutexes in ways that aren't always conveniently nestable, it also provides explicit `lock`, `unlock` methods as well as a failable `tryLock`  method that allows you to specify a time-out.

### Future

This implementation allows you use the typical fluid style you see in most libraries, but it also allows you to use the `Future` as a genuine place-holder for a value, similar to C++'s `std::future`, that you can store away and query when you need it.  It also allows you to specify a timeout for both usages.

### Promise

`Promise` is the necessary but usually hidden counterpart of `Future`.   Even though its interface is really simple, if you mainly just need to get a `Future` from  `async`, you'll never need to create a `Promise` yourself.  On the other hand, you can use `Promise` to return a `Future` from any code you like, for example your own wrapper around a third party asynchronous library.


## Basic Usage

Although each function  and type is fully documented with markup comments, so in Xcode you can easily get a reference with QuickLook, it is helpful to see at least basic examples as a starting point.  I'll present these in the order I think most people will use them.

### Future and async

`Future` doesn't make a lot of sense in isolation, so I'll describe it in conjuntion with `async`, but understand that fundamentally the only way to obtain a `Future` directly is from a `Promise`, which will be described later.  `async` uses `Promise` internally to return a `Future`.  There's nothing special about this, and you can do that yourself to use `Future` in other contexts.

You can think of a `Future` in several ways, and they are all simultaneously true:

- It is the receiver side of a one-shot, one-way communicaton channel for the result of a closure.  `Promise` is the sender end of that channel.
- It is a placeholder for some result to be set by some other code in the future, possibly in another thread of execution.
- It is a means of specifying completion handlers to be executed when a closure returns or throws, possibly in another thread of execution.

The implementation of `async` in this package, differs from GCD's native `async` and `asyncAfter` methods in two ways.  The first is that it returns a `Future`, and the second is that there are global free function variants that use a default concurrent `DispatchQueue`, in addition to methods on `DispatchQueue` itself.

When you call `async`, it schedules your closure for execution, like GCD's native `async`, but it also immediately returns a `Future` for the value your closure will return, or the error it will throw.  You can hold on to this `Future` as a means for querying for your closure's eventual result, or you can use it to attach handlers... or both.  The two ways of using it can be used together, if that makes sense for your application.

#### `Future` handler attachment

As a basic example, let's say we have a long-running function, `foo() throws -> Int`.  We can schedule `foo` with `async`, and attach handlers to the returned `Future` like so:

    async { return try foo() }.onSuccess {
        print("foo returned \($0)")
    }.onFailure {
        print("foo threw exception, \($0.localizedDescription)")
    }

`foo` will run concurrently, and if it eventually returns a value, the closure passed to `.onSuccess` will be called with that value.   If on the other hand, `foo` throws, the closure passed to `.onFailure` is called with the error.

Notice how the `Future` doesn't explicitly appear in the above code, but it's there.  It's what `async` returns, in this case, `Future<Int>`, and it's that `Future`'s `onSuccess` method that we're calling to specify the success handler.  `.onSuccess` returns the same `Future`, which allows us to chain a `.onFailure` method call to schedule our failure handler.    It is functionally equivalent to:


    let future = async { return try foo() }

    future.onSuccess {
        print("foo returned \($0)")
    }

    future.onFailure {
        print("foo threw exception, \($0.localizedDescription)")
    }


You can attach handlers in any order, if you prefer to put the failure handler first.

If you prefer to use Swift's `Result` type, you can use a more general `.onCompletion` handler:

    async { return try foo() }.onCompletion {
        switch $0 {
            case let .success(value): 
                print("foo returned \(value)")
            case let .failure(error): 
                print("foo threw exception, \(error.localizedDescription)")
        }
    }

You can specify as many handlers as you like, mixing and matching, completion handlers, success handlers, and failure handlers.  All applicable handlers will be called in the order they are attached.  This allows you to return the future you got from `async` so that code further up the call chain can attach their own handlers.

You can also specify a time-out for the `Future` using the same fluid style.  See the comment documentation for `Future` for more information on that.


#### `Future` as a placeholder

As an alternative to the fluid, functional-like, usage above, you can use `Future` in a more traditionally imperative way, as a placeholder for a yet to be determined value.   Used this way, it's much more like C++'s `std::future`.   We'll use the same `foo` from the previous examples:

    let future = async { return try foo() }

    // future.value and future.error will block until the foo returns or throws
    if let value = future.value {
        print("foo returned \(value)")
    }
    else if let error = future.error {
        print("foo threw exception, \(error.localizedDescription)")
    }

Here, we query for a value by accessing the `.value` property, and for an error via the `.error` property.  These properties *only* return when the future is ready, meaning that `foo` has either returned a value or thrown an error.  Until then, they just block, waiting for `foo` to complete.   When `foo` does complete, if it returns a value, `.value` will contain that value, and `.error` will be `nil`.   If `foo` throws an error, then `.value` will be `nil`, and `.error` will contain the error.

This blocking behavior is useful if the next bit of code depends on the value returned by `foo`, but it can be a problem if we could do other work while we wait for the `Future` to be ready, because it stops our current thread in its tracks until `foo` is done, in which case, we don't get much value from using `async`.  For this reason, the ability to determine if the `Future` is ready without blocking is essential.  You can do this with the `.isReady` property:

    let future = async { return try foo() }

    while !future.isReady {
        // Do some other work while we wait
    }

    if let value = future.value {
        print("foo returned \(value)")
    }
    else if let error = future.error {
        print("foo threw exception, \(error.localizedDescription)")
    }

As with completion handlers, if you prefer to use Swift's `Result` type, you can access the `.result` property instead of `.value` and `.error`:

    let future = async { return try foo() }

    // future.result will block just until future is ready
    switch future.result {
        case let .success(value): 
            print("foo returned \(value)")
        case let .failure(error): 
            print("foo threw exception, \(error.localizedDescription)")
    }

`.result` will block in exactly the same way as `.value` and `.error`.

Any handlers that have been attached will still be run.    The two styles of use can be used together.

If you don't need the actual result (perhaps your closure returns `Void`), you can simply call the `.wait()` method

    let future = async { let _ = try foo() }

    future.wait() // block until future is ready

    // Now the future is ready, so do other stuff

If you're not going to do other work while you wait for the `Future` to be ready, it's far more efficient to call `.wait()` rather than looping on `.isReady`, because all of `Future's` locking methods and properties use `DispatchSemaphore` under the hood, which can truly suspend the thread, whereas spinning on `.isReady` will consume CPU cycles unnecessarily.

#### `async` variations

All of the `async` variants allow you to specify quality of service (qos), and flags just as the GCD native `async` and `asyncAfter` do, and use the same default values when you don't specify them.

The following examples use the global async free functions, but the `DispatchQueue` extension provides equivalent instance methods with the same signatures as the global functions, so you can call them on a specific `DispatchQueue`.

If you need to delay execution of your closure until a specific point in time, you can use the `afterDeadline` variant to specify a `DispatchTime` or `Date`

    let deadline: DispatchTime = .now() + .milliseconds(1000)
    
    // Some time later...
    let future = async(afterDeadline: deadline) {
        return try foo()
    }
    
To specify a delay interval using just `DispatchTimeInterval`, you can use the `afterInterval` variant

    let future = async(afterInterval: .milliseconds(1000)) {
        return try foo()
    }

Alternatively, you can specify the delay as a `TimeInterval` in seconds, using the `afterSeconds` variant

    let future = async(afterSeconds: 1) { return try foo() }

### `sync`

`sync` works exactly the same as `async`, including the variants, except that the closure passed to it is run immediately in the current thread, so the `Future` it returns is immediately ready, and any handlers you attach will be executed as soon as they are attached, if they apply.   Otherwise everything said for `async` applies to `sync`


### `Mutex`

One unfortunate side effect of concurrent code, such as that executed by `async`, is that any mutable shared data that could be accessed by multiple tasks simultaneously must be guarded to avoid data races.  That's what `Mutex` is for.   You create a `Mutex` to guard some data, and then lock it before accessing the shared data, and unlock it afterwards.   Explicitly having to lock and unlock the `Mutex` is error prone, *so the preferred way to use this implementation of `Mutex` is through its `withLock` method*.   As an example, here's a simple implemenation of a `SharedStack`:

    class SharedStack<T>
    {
        private var data = [T]()
        private var mutex = Mutex()
        
        public var isEmpty: Bool {
            return mutex.withLock { data.isEmpty }
        }
        
        public init() {}
        
        public func push(_ value: T) {
            mutex.withLock { data.append(value) }
        }
        
        public func pop() -> T? {
            return mutex.withLock { 
                return data.isEmpty ? nil : data.removeLast() 
            }
        }
    }

`withLock` blocks until the a lock can be obtained, and once obtained, it executes the closure passed to it, and unlocks before returning.  The unlock happens immediately after the closure completes, regardless of whether it returns or throws.

`Mutex` also provides a failable `withAttemptedLock` method that allows you specify a time-out, possibly none, after which it will stop waiting for a lock and throws `MutexError.lockFailed`.  If it fails, the lock is not obtained and the closure is not run.

Although explicitly locking and unlocking the `Mutex` is error-prone, there are circumstances when neither `withLock` nor `withAttemptedLock` will do the job, such as interleaving locking and unlocking multiple mutexes in ways that are neither exclusive to one another, nor cleanly nestable.  For those cases, `Mutex` also provides `lock()`, `tryLock()`, and `unlock()` methods.  Prefer `withLock` and `withAttemptedLock` when you can use them, but if you must explicitly lock and unlock the mutex yourself it is your responsibility to ensure that each `lock()` or successful `tryLock()` is balanced by exactly one `unlock()`, otherwise, you'll deadlock, or crash when the `Mutex` is deinitialized. 

Refer to comment documentation for more information on these other methods.

### `Promise`

If you wish to return a `Future` in your own custom code, you do so by creating a `Promise` and returning its `.future` property in the immediate context, while passing the closure that returns the value, possibly throwing an error,  to the `set(from:)` method in the dispatched context.

As an example, let's suppose you want to wrap `URLSession.dataTask` to return a `Future` to the resulting `Data`.

    extension URLSession
    {
        func dataFuture(with url: URL) -> Future<Data>
        {
            let promise = Promise<Data>()
            
            let task = self.dataTask(with: url) {
                (data, response, error) in
            
                // ignoring response for this example
                promise.set {
                    if let error = error {
                        throw error
                    }
                    return data ?? Data()
                }
            }
            task.resume()
            return promise.future
        }
    }


This example ignores `response`, but if `dataTask` results in an error, throwing that error in the closure we pass to `set` will set the `error` in the returned `Future`.   If there is no error, returning the `data` in the closure passed to `set` will set the `value` in the returned `Future`.  In this example, we return a `Future` instead of a `URLSessionDataTask`, so we also auto-resume the task returned from `dataTask` before returning.


`Promise` also provides a `setResult(from:)` method that takes a *non-throwing* closure that returns a Swift `Result`: 

    extension URLSession
    {
        func dataFuture(with url: URL) -> Future<Data>
        {
            let promise = Promise<Data>()
            
            let task = self.dataTask(with: url) {
                (data, response, error) in
            
                // ignoring response for this example
                promise.setResult { () -> Result<Data, Error> in
                    if let error = error {
                        return .failure(error)
                    }
                    return .success(data ?? Data())
                }
            }
            task.resume()
            return promise.future
        }
    }
