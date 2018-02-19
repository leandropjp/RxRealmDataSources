//
//  Run.swift
//  RxRealmDataSources_Example
//
//  Created by Vasyl Myronchuk on 2/18/18.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import RealmSwift

class Run: Object {
    let timers = List<Timer>()
}
