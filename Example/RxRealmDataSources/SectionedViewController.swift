//
//  SectionedViewController.swift
//  RxRealmDataSources_Example
//
//  Created by Vasyl Myronchuk on 2/18/18.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import UIKit
import RealmSwift

import RxSwift
import RxCocoa
import RxRealm
import RxRealmDataSources

class SectionedViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!

    static let config: Realm.Configuration = {
        var config = Realm.Configuration.defaultConfiguration
        config.inMemoryIdentifier = UUID().uuidString
        return config
    }()

    private var lapsRandomizers = [DataRandomizer<Lap>]()

    private lazy var data: DataRandomizer<Timer> = {
        let realm = try! Realm(configuration: type(of: self).config)
        try! realm.write { realm.add(Run()) }
        let timers = { (realm: Realm) -> List<Timer> in realm.objects(Run.self).first!.timers }
        return DataRandomizer(config: type(of: self).config, collection: timers, create: { [weak self] in
            guard let `self` = self else { return Timer() }
            let timer = Timer()
            let uuid = timer.uuid
            let predicate = NSPredicate(format: "uuid == %@", uuid)
            let laps = { (realm: Realm) -> List<Lap> in realm.objects(Timer.self).filter(predicate).first!.laps }
            let lapsRandomizer: DataRandomizer<Lap> = DataRandomizer(config: type(of: self).config, collection: laps) { lap in
                lap.text = ">" + lap.text
            }
            self.lapsRandomizers.append(lapsRandomizer)
            lapsRandomizer.start()
            return timer
        }, update: { timer in
            timer.dummy += "+"
        })
    }()

    private let bag = DisposeBag()

    deinit {
        print("\(self) died!")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // initialize data store
        _ = data

        // create data source
        let dataSource = RxTableViewRealmSectionedDataSource(cellIdentifier: "Cell", cellType: PersonCell.self,
        cellConfig: { cell, ip, lap in
            cell.customLabel.text = "\(ip.row). \(lap.text)"
        }, sectionRowsFactory: { (timer: Timer) -> AnyRealmCollection<Lap> in
            return timer.laps.toAnyCollection()
        })

        // RxRealm to get Observable<Results>
        let realm = try! Realm(configuration: type(of: self).config)
        let timers = Observable.changeset(from: realm.objects(Run.self).first!.timers)

        // bind to table view

        timers
            .bind(to: tableView.rx.items(dataSource: dataSource))
            .disposed(by: bag)

        let laps = Observable.collection(from: realm.objects(Lap.self))
        laps
            .map { String($0.count) }
            .bind(to: rx.title)
            .disposed(by: bag)

        // demo inserting and deleting data
        data.start()
    }
}
