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
        let dataFont:Font = Font.system(size: 32, weight: .bold, design: .monospaced)
        let timeFont:Font = Font.headline.monospacedDigit()
        return (
        Text(dataManager.screenText)
            + (Text(dataManager.screenTire1Pres+"\t\t").font(dataFont) as Text)
            + (Text("psi").font(timeFont) as Text)
            + (Text("\t\t\t"+dataManager.screenTire2Pres).font(dataFont) as Text)
            + (Text("\n") as Text)
            + (Text(dataManager.screenTire1Temp+"\t\t").font(dataFont) as Text)
            + (Text("ºF").font(timeFont) as Text)
            + (Text("\t\t\t"+dataManager.screenTire2Temp).font(dataFont) as Text)
            + (Text("\n") as Text)
            + (Text(dataManager.screenTire1Time+"\t\t\t\t").font((timeFont)) as Text)
            + (Text("sec").font(timeFont) as Text)
            + (Text("\t\t\t"+dataManager.screenTire2Time).font(timeFont) as Text)
            + (Text("\n\n\n") as Text)
            + (Text(dataManager.screenTire3Pres+"\t\t").font(dataFont) as Text)
            + (Text("psi").font(timeFont) as Text)
            + (Text("\t\t\t"+dataManager.screenTire4Pres).font(dataFont) as Text)
            + (Text("\n") as Text)
            + (Text(dataManager.screenTire3Temp+"\t\t").font(dataFont) as Text)
            + (Text("ºF").font(timeFont) as Text)
            + (Text("\t\t\t"+dataManager.screenTire4Temp).font(dataFont) as Text)
            + (Text("\n") as Text)
            + (Text(dataManager.screenTire3Time+"\t\t\t\t").font((timeFont)) as Text)
            + (Text("sec").font(timeFont) as Text)
            + (Text("\t\t\t"+dataManager.screenTire4Time).font(timeFont) as Text)
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let dm = DataDelegate()
        return ContentView(dataManager: dm)
    }
}
