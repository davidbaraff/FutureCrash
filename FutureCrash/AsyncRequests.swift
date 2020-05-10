//
//  AsyncRequests.swift
//  FutureCrash
//
//  Created by David Baraff on 5/9/20.
//

import Foundation
import Combine

extension Publisher {
    public func blockTillCompletion(_ q: DispatchQueue) throws -> Output {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Output?
        var failure: Failure?
        
        var cancellable: Cancellable?
        cancellable = self.sink(receiveCompletion: { completion in
            switch completion {
            case .failure(let error):
                failure = error
                cancellable?.cancel()
                semaphore.signal()
            case .finished:
                ()
            }
        }) { value in
            result = value
            cancellable?.cancel()
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .distantFuture)
        
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
public func pretendToQuery(_ q : DispatchQueue) -> AnyPublisher<Data, Error> {
    let future = Future<Data, Error> { promise in

        // Change 0.0001 to 0.001 to decrease the odds of it crashing, and
        // make it easier to watch the memory leak.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.0001) {
            q.sync {
                let result = Data(count: 1024)
                promise(.success(result))
            }
        }
    }
    
    return future.eraseToAnyPublisher() // .receive(on: q).eraseToAnyPublisher()
}

private let _workQueue = DispatchQueue(label: "com.deb.work", attributes: .concurrent)

private func perpetualWorker(index: Int) {
    var ctr = 0
    let q = DispatchQueue(label: "com.deb.worker.\(index)")
    while true {
        autoreleasepool {
            let f = pretendToQuery(q)
            /*
            let result = try! f.blockTillCompletion(q)

            if result.isEmpty {
                fatalError("Got back empty data")
            }*/

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

