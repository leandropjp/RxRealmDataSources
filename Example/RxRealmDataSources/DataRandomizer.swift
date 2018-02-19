//
//  DataRandomizer.swift
//  RxRealmDataSources
//
//  Created by Marin Todorov on 12/11/16.
//  Copyright © 2016 RxSwiftCommunity. All rights reserved.
//

import Foundation
import RealmSwift
import RxSwift

extension Int {
    public func random(_ modifier: Int = 0) -> Int {
        return Int(arc4random_uniform(UInt32(self + modifier)))
    }
}

class DataRandomizer<T: Object> {

    private let config: Realm.Configuration
    private let collection: (Realm) -> List<T>
    private let create: () -> T
    private let update: (T) -> Void
    private var bag = DisposeBag()

    private lazy var realm: Realm = {
        let realm: Realm
        do {
            realm = try Realm(configuration: self.config)
            return realm
        }
        catch let e {
            print(e)
            fatalError()
        }
    }()

    init(config: Realm.Configuration, collection: @escaping (Realm) -> List<T>, create: @escaping () -> T = { T() }, update: @escaping (T) -> Void) {
        self.config = config
        self.collection = collection
        self.create = create
        self.update = update
    }

    deinit {
        print("\(self) died!!!")
    }

    private func insertRow() {
        write { [weak self] realm in
            guard let `self` = self else { return }
            let collection = self.collection(realm)
            let index = collection.count.random(1)
            collection.insert(self.create(), at: index)
            print("insert at [\(index)]")
        }
    }

    private func updateRow() {
        write { [weak self] realm in
            guard let `self` = self else { return }
            let collection = self.collection(realm)
            let index = collection.count.random()
            self.update(collection[index])
            print("update at [\(index)]")
        }
    }

    private func deleteRow() {
        write { [weak self] realm in
            guard let `self` = self else { return }
            let collection = self.collection(realm)
            let index = collection.count.random()
            collection.remove(at: index)
            print("delete from [\(index)]")
        }
    }

    private func write(_ block: @escaping (Realm) -> Void) {
        let config = self.config
        writeQueue.async {
            autoreleasepool {
                do {
                    let realm = try Realm(configuration: config)
                    try realm.write { block(realm) }
                } catch {
                    print(error)
                }
            }
        }
    }

    func start() {
        print("Starting with \(T.self)")

        for _ in 1...1 {
            insertRow()
            insertRow()
            insertRow()
            insertRow()
            insertRow()
        }

        // insert some laps
        Observable<Int>.interval(1.0, scheduler: MainScheduler.instance)
            .subscribe(onNext: {[weak self] _ in
                self?.insertRow()
            })
            .disposed(by: bag)

        for _ in 0..<1 {
            Observable<Int>.interval(1.0, scheduler: MainScheduler.instance)
                .subscribe(onNext: {[weak self] _ in
                    self?.updateRow()
                })
                .disposed(by: bag)
        }
        
        Observable<Int>.interval(3.4, scheduler: MainScheduler.instance)
            .subscribe(onNext: {[weak self] _ in
                self?.deleteRow()
            })
            .disposed(by: bag)
    }

    func stop() {
        bag = DisposeBag()
    }
}

private let writeQueue = DispatchQueue(label: "Realm.write.queue", qos: .utility)
