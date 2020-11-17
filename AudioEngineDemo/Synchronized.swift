//
//  Synchronized.swift
//  AudioEngineDemo
//
//  Created by Josh Elkins on 11/15/20.
//

import Foundation


// A simple property wrapper for a value that may be
// safely accessed from multiple threads.
@propertyWrapper
public class Synchronized<T> {
    private var accessQueue = DispatchQueue(label: "com.jbelkins.Synchronized<\(T.self)>", qos: .userInteractive)
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
}
