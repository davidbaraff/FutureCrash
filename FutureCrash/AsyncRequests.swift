//
//  AsyncRequests.swift
//  FutureCrash
//
//  Created by David Baraff on 5/9/20.
//

import Foundation
import Combine

let lock1 = DispatchQueue(label: "xxx1")
var bbb = -1
func blockCtr() -> Int {
    return lock1.sync { bbb }
}

func setBlockCtr(_ val: Int) {
    lock1.sync { bbb = val }
}

extension Publisher {
    public func blockTillCompletion(q: DispatchQueue) throws -> Output {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Output?
        var failure: Failure?
        
        let cancellable: Cancellable = q.sync {
            self.sink(receiveCompletion: { completion in
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
        }

        _ = semaphore.wait(timeout: .distantFuture)
        q.sync { cancellable.cancel() }

        if let result = result {
            return result
        }
        
        throw failure!
    }
}

public func pretendToQuery(_ q : DispatchQueue) -> AnyPublisher<Data, Error> {
    let ps = PassthroughSubject<Data, Error>()
    let task = {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.0001) {
            q.sync {
                ps.send(Data(count: 1024))
            }
        }
    }
    
    return ps.receive(on: q).handleEvents(receiveSubscription: { _ in task() }).eraseToAnyPublisher()
}

public func pretendToQueryUsingFuture(_ q : DispatchQueue) -> AnyPublisher<Data, Error> {
    let future = Future<Data, Error> { promise in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.0001) {
            q.sync {
                promise(.success(Data(count: 1024)))
            }
        }
    }
    
    return future.eraseToAnyPublisher()

}

private func worker(index: Int, base: Int) {
    let q = DispatchQueue(label: "com.deb.worker.\(index)")
    for ctr in 0...5000 {
        let f = pretendToQueryUsingFuture(q)
        let data = try! f.blockTillCompletion(q: q)

        if data.count != 1024 {
            fatalError("Bad data result: \(data.count)")
        }
        if ctr % 100 == 0 {
            print("[\(index)] Worker reached", ctr + base)
        }
    }
    
    DispatchQueue.global().async {
        worker(index: index, base: base + 5000)
    }
}

public func startWorkers() {
    for i in 0..<8 {
        DispatchQueue.global().async {
            worker(index: i, base: 0)
        }
    }
}

