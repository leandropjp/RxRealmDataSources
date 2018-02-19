//
//  RxTableViewRealmSectionedDataSource.swift
//  Pods-Demo-RxRealmDataSources_Example
//
//  Created by Vasyl Myronchuk on 2/2/18.
//

import Foundation
import UIKit

import RealmSwift
import RxSwift
import RxCocoa
import RxRealm
import RxRealmDataSources // TODO: remove

open class RxTableViewRealmSectionedDataSource<S: Object, R: Object>: NSObject, UITableViewDataSource, RxTableViewDataSourceType, SectionedViewDataSourceType {

    private weak var tableView: UITableView!

    private var sections: AnyRealmCollection<S>!
    private var sectionsCount = 0
    private var sectionInfos = [Int: SectionInfo<R>]()

    public typealias SectionRowsFactory<S: Object, R: Object> = (S) -> AnyRealmCollection<R>
    public var sectionRowsFactory: SectionRowsFactory<S, R>

    public typealias TableCellFactory<S: Object, R: Object> = (RxTableViewRealmSectionedDataSource<S, R>,
                                                               UITableView, IndexPath, R) -> UITableViewCell
    public typealias TableCellConfig<R: Object, CellType: UITableViewCell> = (CellType, IndexPath, R) -> Void

    public let cellIdentifier: String
    public let cellFactory: TableCellFactory<S, R>

    public init(cellIdentifier: String,
                cellFactory: @escaping TableCellFactory<S, R>,
                sectionRowsFactory: @escaping SectionRowsFactory<S, R>) {
        self.cellIdentifier = cellIdentifier
        self.cellFactory = cellFactory
        self.sectionRowsFactory = sectionRowsFactory
    }

    public init<CellType>(cellIdentifier: String, cellType: CellType.Type,
                          cellConfig: @escaping TableCellConfig<R, CellType>,
                          sectionRowsFactory: @escaping SectionRowsFactory<S, R>) where CellType: UITableViewCell {
        self.cellIdentifier = cellIdentifier
        self.cellFactory = { ds, tv, ip, model in
            let cell = tv.dequeueReusableCell(withIdentifier: cellIdentifier, for: ip) as! CellType
            cellConfig(cell, ip, model)
            return cell
        }
        self.sectionRowsFactory = sectionRowsFactory
    }

    deinit {
        print("\(self) died!")
    }

    // MARK: - Configuration

    public var animated = true
    public var sectionAnimations = (
        insert: UITableViewRowAnimation.automatic,
        update: UITableViewRowAnimation.automatic,
        delete: UITableViewRowAnimation.automatic)

    public var rowAnimations = (
        insert: UITableViewRowAnimation.automatic,
        update: UITableViewRowAnimation.automatic,
        delete: UITableViewRowAnimation.automatic)

    public var reloadsSectionsOnUpdate = false

    // MARK: - SectionedViewDataSourceType

    public func model(at indexPath: IndexPath) throws -> Any {
        return item(at: indexPath)
    }

    // MARK: - RxTableViewDataSourceType

    public func tableView(_ tableView: UITableView, observedEvent: Event<RealmChange<S>>) {
        if self.tableView == nil { self.tableView = tableView }
        guard self.tableView == tableView else {
            assertionFailure("Event from other table view")
            return
        }

        Binder(self) { dataSource, element in
            dataSource.applySectionChanges(to: tableView, items: element.0, changes: element.1)
        }.on(observedEvent)
    }

    // MARK: - UITableViewDataSource

    public func numberOfSections(in tableView: UITableView) -> Int {
        let result = sectionsCount
        print("\(#function) is \(result)")
        return result
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let result = sectionRows(at: section).count
        print("\(#function) \(section): \(result)")
        return result
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        print("\(#function) \(indexPath)")
        return cellFactory(self, tableView, indexPath, item(at: indexPath))
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Section: \(section)"
    }

    // MARK: - Private

    private func sectionRows(at section: Int) -> SectionInfo<R> {
        if let sectionInfo = sectionInfos[section] { return sectionInfo }

        let rows = sectionRowsFactory(sections[section])
        let sectionInfo = SectionInfo(section: section, rows: rows)
        sectionInfos[section] = sectionInfo

        DispatchQueue.main.async { // DIRTY HACK!!!
            Observable.changeset(from: rows).subscribe { [weak self, weak sectionInfo] event in
                guard let `self` = self else { return }
                Binder(self) { [weak sectionInfo] dataSource, element in
                    guard let tableView = dataSource.tableView, let sectionInfo = sectionInfo else { return }
                    dataSource.applyRowChanges(to: tableView, section: sectionInfo.section, items: element.0, changes: element.1)
                }.on(event)
            }.disposed(by: sectionInfo.bag)
        }

        return sectionInfo
    }

    private func item(at indexPath: IndexPath) -> R {
        return sectionRows(at: indexPath.section).rows[indexPath.row]
    }

    private func updateSectionsIndices(_ changes: [Int], shift: Int = 1) {
        guard changes.count > 0 else { return }
        for insertedIndex in changes {
            var updatedSectionInfos = [Int: SectionInfo<R>]()
            self.sectionInfos.forEach { section, info in
                let indexAfterChange = section + (section < insertedIndex ? 0 : shift)
                info.section = indexAfterChange
                updatedSectionInfos[indexAfterChange] = info
            }
            sectionInfos = updatedSectionInfos
        }
    }

    // MARK: - Applying changeset to the table view

    private func applySectionChanges(to tableView: UITableView, items: AnyRealmCollection<S>, changes: RealmChangeset?) {
//        print("Sections: \(changes)")

        if sections == nil {
            sections = items
        }
        sectionsCount = items.count // Caching is required due to notifications delivering race conditions

        // if view is not in view hierarchy, performing batch updates will crash the app
        if tableView.window == nil {
            tableView.reloadData()
            return
        }

        guard animated, let changes = changes else {
            tableView.reloadData()
            return
        }

        let lastSectionCount = tableView.numberOfSections
        guard items.count == lastSectionCount + changes.inserted.count - changes.deleted.count else {
            tableView.reloadData()
            return
        }

        changes.deleted.forEach { self.sectionInfos[$0] = nil }
        if reloadsSectionsOnUpdate {
            changes.updated.forEach { self.sectionInfos[$0] = nil }
        }
        updateSectionsIndices(changes.deleted, shift: -1)
        updateSectionsIndices(changes.inserted)

        tableView.beginUpdates()
        tableView.deleteSections(IndexSet(changes.deleted), with: sectionAnimations.delete)
        tableView.insertSections(IndexSet(changes.inserted), with: sectionAnimations.insert)
        if reloadsSectionsOnUpdate {
            tableView.reloadSections(IndexSet(changes.updated), with: sectionAnimations.update)
        }
        tableView.endUpdates()
    }

    private func applyRowChanges(to tableView: UITableView, section: Int, items: AnyRealmCollection<R>, changes: RealmChangeset?) {
        print("Rows at section \(section) is \(items.count): \(changes)")

        // Workaround
        if let sectionInfo = sectionInfos[section] {
            sectionInfo.count = sectionInfo.rows.count
        }

        // Rows notification delivery may happen before sections notification
        if sectionsCount != sections.count {
            sectionsCount = sections.count
            tableView.reloadData()
            return
        }

        // if view is not in view hierarchy, performing batch updates will crash the app
        if tableView.window == nil {
            tableView.reloadData()
            return
        }

        guard animated, let rowChanges = changes else {
            tableView.reloadSections(IndexSet(integer: section), with: sectionAnimations.update)
            return
        }

        let lastRowCount = tableView.numberOfRows(inSection: section)
        guard items.count == lastRowCount + rowChanges.inserted.count - rowChanges.deleted.count else {
            tableView.reloadSections(IndexSet(integer: section), with: sectionAnimations.update)
            return
        }

        let fromRow = { row in IndexPath(row: row, section: section) }

        tableView.beginUpdates()
        tableView.deleteRows(at: rowChanges.deleted.map(fromRow), with: rowAnimations.delete)
        tableView.insertRows(at: rowChanges.inserted.map(fromRow), with: rowAnimations.insert)
        tableView.reloadRows(at: rowChanges.updated.map(fromRow), with: rowAnimations.update)
        tableView.endUpdates()
    }
}

class SectionInfo<R: Object> {
    var section: Int // NB: section index may change at any time
    let rows: AnyRealmCollection<R>
    var count: Int // Caching is required due to notifications delivering race conditions
    let bag = DisposeBag()

    init(section: Int, rows: AnyRealmCollection<R>) {
        self.section = section
        self.rows = rows
        self.count = rows.count
    }

    deinit {
        print("Bye-bye to section \(section)")
    }
}
