//
//  Promise.swift
//  FuzzyBTC2
//
//  Created by Chip Jarred on 1/16/18.
//  Copyright © 2018 Chip Jarred. All rights reserved.
//

import Foundation

// ------------------------------------------
@dynamicCallable
public struct Promise<T>
{
	let future:Future<T>
    
    public func callAsFunction
	
	// ------------------------------------------
	public init() {
		self.future = Future<T>()
	}
    
//    public init<R>(body: () throws -> R)
//    {
//        self.future = Future<T>()
//        do
//        {
//            let result = try body()
//            self.future.set(value: result)
//        }
//        catch { self.future.set(error: error) }
//    }
	
	// ------------------------------------------
	public func set(value:T) {
		future.set(value: value)
	}
	
	// ------------------------------------------
	public func set(error: Error) {
		future.set(error: error)
	}
}
