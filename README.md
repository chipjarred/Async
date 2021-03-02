#  Async

`Async` is a free-to-use framework of functions and types that I have found incredibly useful in working with *Grand Central Dispatch*, although the work horses of the library, `Future` and its coresponding `Promise`,  are useful in a wider variety of contexts.   I've been using these in my own code for a long time, and have always meant to share them, so now I finally am.   I have other types and functions I have found useful that I may add later, but these form the core functionality I use nearly every time I use GCD. 

Even though `Future` is really the central feature, the library is called `Async` because it provides global `async` free functions and adds coresponding methods on `DispatchQueue` that return a `Future`, so I almost never need to explictly create a `Promise` , and often the `Future` itself just disappears behind fluid completion handler syntax, so that it almost seems as though the library is about `async`.   But actually `Future` is the hero, and it's more flexible than most `Future` implementations I've seen.

I often try an idea by using writing a command line tool rather than an actual AppKit/UIKit application, so this package is specifically designed to be independent of those.  It uses only GCD and Foundation.

## What's Included

### async

There are a  few variations of a global  `async` free function that immediately return a `Future`, asynchronously executing your closure, which can safely throw an error, on a global default concurrent `DispatchQueue`. You don't need to create a queue explictly yourself, unless you just need it for some other reason.  

I provide a few variations, because I find it annoying that it's necessary to specify a deadline in GCD's `asyncAfter` as a `DispatchTime`.  I almost always want my code to run either as soon as possible or after a specified delay from the moment I called `async`, and nearly never need it to run at a specific point in time.  So I provide variations on my `async` function that allow you specify a deadline as a `DispatchTime`, as with GCD's native version, or a delay as `DispatchTimeInterval` or `TimeInterval`.

### sync

There are *synchronous* versons of the global  `async` free functions.  They merely run your closure immediately in the current thread as though you had called it directly yourself.  This is useful for several reasons:
        
• It allows an intermediate step in refactoring synchronous code into asynchronous during which you are still executing a closure synchronously while getting a `Future` from it.  In that case, the `Future` is ready immediately when your closure returns, and if you added handlers, they are called immediately.   Then by simply changing `sync` to `async`, it becomes truly asynchronous.   

• It is sometimes helpful for debugging to use `sync`  instead of `async` temporarily, and it is a simple one-letter code change.   

• It returns a `Future`, so you can use it inside of your own code as an easy way to return a `Future` without worrying about how to use `Promise`, although `Promise` is pretty easy to use directly.


### DispatchQueue extension

`async` and `sync` methods have been added to `DispatchQueue` to corespond to their global versions, but you get the `Future` returning behavior on the queue of your choice instead of the default global concurrent queue.

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

Attaching handlers (callbacks) to a `Future` is the easiest and safest way to keep your code from blocking on a result, since you can just continue on doing something else after attaching them, and your handlers will be called automatically when your asynchronous code completes.  In terms of ease of use and safety, handlers are normally the way to go.  

They do have some drawbacks though.  If you're combining the results of several asynchronous tasks that must all complete before progress can be made, handlers can be awkward.  For example, in a computation graph, all input computations must complete before the current node can be evaluated.   In that case the current computation should block until the inputs are ready.  Of course, you could force the square peg of handlers into this round hole, but that's not a good use case for handlers.  You'd need to update some counter for inputs, ensure that updates to that counter from multiple handlers happen atomicly, and block on that counter.  It's not that hard, but what a needless, inefficient and error-prone mess!  By comparison, it's ideal for using collection of `Future`s as placeholders.  Just iteratively wait on each of them.  When the loop completes they're all ready, and you can proceed to evaluate the current node.  This is exactly why I provide that alternative.

On the other hand, fetching data from a network or responding to events, very common cases, are usually ideal uses of handlers, and keeping a `Future` for a placeholder becomes the awkward one, because it requires you either to block until it's ready, or to write some kind of loop or other scheme to continually check when it's ready while your code continues.

Having said that completion handlers are a good fit for callbacks, such as for HTTP requests, using them as placeholders is a good way to avoid deeply nested callbacks when the results of one request require spawning another request, and another. 

The implementation of `async` in this package, differs from GCD's native `async` and `asyncAfter` methods in two ways.  The first is that it returns a `Future`, and the second is that there are global free function variants that use a default concurrent `DispatchQueue`, in addition to methods on `DispatchQueue` itself.

When you call `async`, it schedules your closure for execution, using GCD's native `async`, but it also immediately returns a `Future` for the value your closure will return, or the error it will throw.  You can hold on to this `Future` as a means for querying for your closure's eventual result, or you can use it to attach handlers... or both.  The two ways of using it can be used together, if that makes sense for your application.

#### `Future` handler attachment

##### `.onSuccess` and `.onFailure`
As a basic example, let's say we have a long-running function, `foo() throws -> Int`.  We can schedule `foo` with `async`, and attach handlers to the returned `Future` like so:

```swift
async { return try foo() }.onSuccess {
    print("foo returned \($0)")
}.onFailure {
    print("foo threw exception, \($0.localizedDescription)")
}
```

`foo` will run concurrently, and if it eventually returns a value, the closure passed to `.onSuccess` will be called with that value.   If on the other hand, `foo` throws, the closure passed to `.onFailure` is called with the error.

Notice how the `Future` doesn't explicitly appear in the above code, but it's there.  It's what `async` returns, in this case, `Future<Int>`, and it's that `Future`'s `.onSuccess` method that we're calling to specify the success handler.  `.onSuccess` returns the same `Future`, which allows us to chain a `.onFailure` method call to schedule our failure handler.    It is equivalent to:

```swift
let future = async { return try foo() }

future.onSuccess {
    print("foo returned \($0)")
}

future.onFailure {
    print("foo threw exception, \($0.localizedDescription)")
}
```


You can attach handlers in any order, if you prefer to put the failure handler first.

##### `.onCompletion`
If you prefer to use Swift's `Result` type, you can use a more general `.onCompletion` handler:

```swift
async { return try foo() }.onCompletion {
    switch $0 {
        case let .success(value): 
            print("foo returned \(value)")
        case let .failure(error): 
            print("foo threw exception, \(error.localizedDescription)")
    }
}
```

You can specify as many handlers as you like, mixing and matching, completion handlers, success handlers, and failure handlers.  All applicable handlers will be called concurrently.  This allows you to return the future you got from `async` so that code further up the call chain can attach their own handlers.


##### `.timeout`
You can also specify a time-out for the `Future` using the same fluid style.  If the specified time-out elapses before the closure completes, an error is set in the `Future` and its `.onFailure` and `.onCompletion` handlers are called.  See the comment documentation for `Future` for more information on that.


#### `Future` as a placeholder

As an alternative to the fluid, functional-like, usage above, you can use `Future` in a more traditionally imperative way, as a placeholder for a yet to be determined value.   Used this way, it's much more like C++'s `std::future`.   This is especially useful when you use `async` to subdivide a larger task into to a number of concurrent subtasks, which must be combined into a final result before continuing.

When using `Future` as a placeholder, you store it away as you might store the actual value returned by the asynchronous code or the error thrown by it, if it had been called synchronously, and then query the `Future` for the value or error some time later when you need it.  To support this, `Future` provides blocking properties and methods to query the future and wait for it to be ready, as well as a non-blocking property to query its ready state.

Any handlers that have been attached will still be run, whether or not you use `Future` as a placeholder.    The two styles of use can be used together.

##### Blocking methods and properties

Be aware that in an AppKit/UIKit application, using blocking methods and properties in the main thread can make your app unresponsive while they block.   Either use them in separate thread that can safely block, use `.isReady` to do something else when the `Future` is not ready, ensure that all asynchronous calls will complete quickly, or just avoid blocking methods and properties altogether by attaching handlers instead. 

###### `.value` and `.error`:
You can obtain the value or error from the future with its `.value` and `.error` properties.  We'll use the same `foo` from the previous examples:

```swift
let future = async { return try foo() }

// future.value and future.error will block until the foo returns or throws
if let value = future.value {
    print("foo returned \(value)")
}
else if let error = future.error {
    print("foo threw exception, \(error.localizedDescription)")
}
```

These properties *only* return when the future is ready, meaning that `foo` has either returned a value or thrown an error.  Until then, they just block, waiting for `foo` to complete.   When `foo` does complete, one of the following will be true:

- If it returns a value, `.value` will contain that value, and `.error` will be `nil`.   
- If it throws an error, `.value` will be `nil`, and `.error` will contain the error.  

The `Future` will never have both an error and a value.

Note that if a `timeout` modifer was set as mentioned above, and the specified time-out elapses before the closure completes, `.error` will contain `FutureError.timedOut`.  


###### `.result`
If you prefer to use Swift's `Result` type, you can access the `.result` property instead of `.value` and `.error`:

```swift
let future = async { return try foo() }

// future.result will block until future is ready
switch future.result {
    case let .success(value): 
        print("foo returned \(value)")
    case let .failure(error): 
        print("foo threw exception, \(error.localizedDescription)")
}
```

`.result` will block in exactly the same way as `.value` and `.error`.

If a `timeout` modifer was set as mentioned above, and the specified time-out elapses before the closure completes, `.result` will be `.failure(FutureError.timedOut)`.  

###### `.getValue()`
If you prefer to use `do {...} catch {...}` blocks for error handling, `Future` provides a throwing `.getValue()` method:

```swift
let future = async { return try foo() }

// future.getValue() will block until the foo returns or throws
do 
{
    let value = try future.getValue()
    print("foo returned \(value)")
}
catch { print("foo threw exception, \(error.localizedDescription)") }
```

###### `.wait()`
If you don't need the actual result (perhaps your closure returns `Void`), you can simply call the `.wait()` method

```swift
let future = async { let _ = try foo() }

future.wait() // block until future is ready

// Now the future is ready, so do other stuff
```
    
`.wait()` also has a time-out variant.  It is different from the `timeout` modifier mentioned above in that it does not set an error in the `Future` when it times out.  It merely stops waiting for the `Future` to be ready, throwing an error itself when it times out.  Refer to `Future`'s comment documentation for more information.


##### Non-blocking methods and properties
###### `.isReady`
The blocking behavior of `.wait()`,  `.value` ,  `.error` and `.result` is useful if the code following them depends on the value returned or error thrown by `foo`, but it can be a problem if you could do other work while you wait for the `Future` to be ready, because it stops your current thread in its tracks until `foo` is done, in which case, you don't get much value from using `async`.  For this reason, the ability to determine if the `Future` is ready without blocking is essential.  You can do this with the `.isReady` property:

```swift
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
```

*If you're not going to do other work while you wait for the `Future` to be ready, it's far more efficient to call `.wait()` rather than looping on `.isReady`, because all of `Future's` blocking methods and properties, including `.wait()`, use `DispatchSemaphore` under the hood, which can truly suspend the thread, whereas spinning on `.isReady` will consume CPU cycles unnecessarily.*

#### `async` variations

All of the `async` variants allow you to specify quality of service (qos), and flags just as the GCD native `async` and `asyncAfter` do, and use the same default values when you don't specify them.

The following examples use the global async free functions, but the `DispatchQueue` extension provides equivalent instance methods with the same signatures as the global functions, so you can call them on a specific `DispatchQueue`.

##### `.async()`
If you want your closure to be executed as soon as possible, you can call it as the previous examples with no deadline or delay interval.

```swift
let future = async { return try foo() }
```

##### `.async(afterDeadline:)`
If you need to delay execution of your closure until a specific point in time, you can use the `afterDeadline` variant to specify a `DispatchTime` or `Date`

```swift
let deadline: DispatchTime = .now() + .milliseconds(1000)

// Some time later...
let future = async(afterDeadline: deadline) {
    return try foo()
}
```
    
##### `.async(afterInterval:)`
To specify a delay interval using just `DispatchTimeInterval`, you can use the `afterInterval` variant

```swift
let future = async(afterInterval: .milliseconds(1000)) {
    return try foo()
}
```

##### `.async(afterSeconds:)`
Alternatively, you can specify the delay as a `TimeInterval` in seconds, using the `afterSeconds` variant

```swift
let future = async(afterSeconds: 1) { return try foo() }
```

### `sync`

`sync` is the synchronous dual of `async`.  It runs the closure passed to it in the current thread before returning.

If no deadline or delay is specified, it will execute the closure immediately.  If a deadline or delay is specified, it will block until the deadline, or delay has elapsed, and then execute the closure.  Because `sync` doesn't return until the closure has been executed, any handlers attached to the `Future` it returns will be executed as soon as they are attached, if they apply.

Otherwise everything said for `async` applies to `sync`.

### `Mutex`

One unfortunate side effect of concurrent code, such as that executed by `async`, is that any mutable shared data that could be accessed by multiple tasks simultaneously must be guarded to avoid data races.  That's what `Mutex` is for.   You create a `Mutex` to guard some data, and then lock it before accessing the shared data, and unlock it afterwards.   Explicitly having to lock and unlock the `Mutex` is error prone, *so the preferred way to use this implementation of `Mutex` is through its `withLock` method*.   As an example, here's a simple implemenation of a `SharedStack`:

```swift
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
```

`withLock` blocks until the a lock can be obtained, and once obtained, it executes the closure passed to it, and unlocks before returning.  The unlock happens immediately after the closure completes, regardless of whether it returns or throws.

`Mutex` also provides a failable `withAttemptedLock` method that allows you specify a time-out, possibly none, after which it will stop waiting for a lock and throws `MutexError.lockFailed`.  If it fails, the lock is not obtained and the closure is not run.

Although explicitly locking and unlocking the `Mutex` is error-prone, there are circumstances when neither `withLock` nor `withAttemptedLock` will do the job, such as interleaving locking and unlocking multiple mutexes in ways that are neither exclusive to one another, nor cleanly nestable.  For those cases, `Mutex` also provides `lock()`, `tryLock()`, and `unlock()` methods.  *Prefer `withLock` and `withAttemptedLock`* when you can use them. **If you must explicitly lock and unlock the mutex yourself, it is your responsibility to ensure that each `lock()` or successful `tryLock()` is balanced by exactly one `unlock()`**, otherwise, you'll deadlock, or crash when the `Mutex` is deinitialized.  This crashing behavior is one that is inherited by its being implemented in terms of `DispatchSemaphore` which crashes when deinitialized with a negative value, which it will have if the `Mutex` is still locked.  This is actually a good thing because it tells you unambiguously that you have a bug.  To paraphrase Apple's documentation on the subject: Don't do that!

Refer to comment documentation for more information on these other methods.

### `Promise`

`Promise` is the sender of the `Promise`/`Future` team.  It's how you obtain a `Future` to return from your own code, and how you set the value in the `Future` from code that may be executed far removed from the code receiving the `Future`, possibly in a completely different thread.

##### `.set(from:)`
If you wish to return a `Future` in your own custom code, you do so by creating a `Promise` and returning its `.future` property in the immediate context, while passing the closure that returns the value, possibly throwing an error,  to the `.set(from:)` method in the dispatched context.

As an example, let's suppose you want to wrap `URLSession`'s `.dataTask` to return a `Future` to the resulting `Data`.

```swift
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
```

The `.set(from:)` method will set the `Future` according to whether the closure returns or throws, which in this case depends on whether `dataTask` calls its completion handler with an error:

- If `.dataTask` calls its completion handler with a non-`nil` error, the closure passed to `.set(from:`) will throw, causing the `Promise` to set the `Future`'s `.error`.
- If `.dataTask` calls its completion handler with a `nil` error, the closure passed to `.set(from:)` will return `data` causing the `Promise` to set the `Future`'s `value` to `data`.

In this example, we ignore `response`, and since we return a `Future` instead of a `URLSessionDataTask`, so we also resume the task returned from `dataTask` before returning.

##### `.setResult(from:)`
`Promise` also provides a `setResult(from:)` method that takes a *non-throwing* closure that returns a Swift `Result`: 

```swift
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
```
