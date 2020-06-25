// This file is part of TireLog by Mike Tigas
//   https://github.com/mtigas/iOS-BLE-Tire-Logger
// Copyright © 2020 Mike Tigas
//   https://mike.tig.as/
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at one of the following URLs:
//   https://github.com/mtigas/iOS-BLE-Tire-Logger/blob/main/LICENSE.txt
//   https://mozilla.org/MPL/2.0/

import SwiftUI


struct ContentView: View {
    @ObservedObject var dataManager: DataDelegate
    
    var body: some View {
        Text(dataManager.screenText).padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let dm = DataDelegate()
        return ContentView(dataManager: dm)
    }
}
