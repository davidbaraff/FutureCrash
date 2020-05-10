//
//  AsyncRequests.swift
//  FutureCrash
//
//  Created by David Baraff on 5/9/20.
//

import Foundation
import Combine

extension Publisher {
    public func blockTillCompletion() throws -> Output {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Output?
        var failure: Failure?
        
        var cancellable: Cancellable? = self.sink(receiveCompletion: { completion in
            switch completion {
            case .failure(let error):
                failure = error
                semaphore.signal()
            case .finished:
                ()
            }
        }) { value in
            result = value
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .distantFuture)
        
        cancellable = nil
        
        if let result = result {
            return result
        }
        
        throw failure!
    }
}

// In a real world example, this function would do a network query and deliver a result (e.g. Data, and HTTPResponse).
// For now, just wait a few ticks and return some Data.

// If you make a bunch of pretendToQuery() calls in parallel,
// your program will crash after just a few seconds.  (I've yet
// to see it run as long as 60 seconds).

// Oh, and did I mention that it leaks memory too?
public func pretendToQuery() -> Future<Data, Error>  {
    let future = Future<Data, Error> { promise in

        // Change 0.0001 to 0.001 to decrease the odds of it crashing, and
        // make it easier to watch the memory leak.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.0001) {
            let result = Data(count: 1024)
            promise(.success(result))
        }
    }
    
    return future
}

private let _workQueue = DispatchQueue(label: "com.deb.work", attributes: .concurrent)

private func perpetualWorker(index: Int) {
    var ctr = 0
    while true {
        autoreleasepool {
            let f = pretendToQuery()
            let result = try! f.blockTillCompletion()

            if result.isEmpty {
                fatalError("Got back empty data")
            }

            ctr += 1
            if ctr % 100 == 0 {
                print("Worker [\(index)]: reached", ctr)
            }
        }
    }
}

private let maxWorkers = 8
public func startWorkers() {
    for i in 0..<8 {
        _workQueue.async {
            perpetualWorker(index: i)
        }
    }
}

