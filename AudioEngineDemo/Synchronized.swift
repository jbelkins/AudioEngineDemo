//
//  Synchronized.swift
//  AudioEngineDemo
//
//  Created by Josh Elkins on 11/15/20.
//

import Foundation


@propertyWrapper
public class Synchronized<T> {
    private var accessQueue = DispatchQueue(label: "com.jbelkins.Synchronized<\(T.self)>")
    private var _wrappedValue: T?

    public init(wrappedValue: T) {
        _wrappedValue = wrappedValue
    }

    public var wrappedValue: T {
        get {
            accessQueue.sync {
                _wrappedValue!
            }
        }
        set {
            accessQueue.sync {
                _wrappedValue = newValue
            }
        }
    }

    public var projectedValue: Synchronized<T> { self }

    public func mutate(_ block: (inout T) -> Void) {
        block(&_wrappedValue!)
    }
}
