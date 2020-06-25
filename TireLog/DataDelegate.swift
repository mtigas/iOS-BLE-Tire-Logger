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

import Foundation
import SwiftUI

import CoreBluetooth
import CoreLocation
import UserNotifications
import os.log

let tpmsServiceCBUUID = CBUUID(string: "0xFBB0")

let saveDebugLog = false
let useOSConsoleLog = false




extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }
    
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined()
    }
}


class DataDelegate:NSObject,ObservableObject {
    @Published var latestRow: String = "timestamp,lat,lon,pos_acc_m,elevation_m,elevation_acc_m,speed_mps,speed_acc_mps,course_deg,course_acc_deg,tire_fl_kpa,tire_fl_c,tire_fr_kpa,tire_fr_c,tire_rl_kpa,tire_rl_c,tire_rr_kpa,tire_rr_c\n"
    
    @Published var screenText: String =
        "..."
    
    let locationManager = CLLocationManager()
    var centralManager: CBCentralManager!

    var latestLoc:CLLocation = CLLocation(latitude: 0, longitude: 0)
    var latestUpdate:Date = Date.init()
    
    var tpms_pressure_kpa : [Double] = [0.0, 0.0, 0.0, 0.0]
    var tpms_temperature_c : [Double] = [0.0, 0.0, 0.0, 0.0]
    var tpms_pressure_kpa_persist : [Double] = [0.0, 0.0, 0.0, 0.0]
    var tpms_temperature_c_persist : [Double] = [0.0, 0.0, 0.0, 0.0]
    var tpms_last_tick : [Date] = [Date(), Date(), Date(), Date()]
    
    var logPath:URL = URL.init(fileURLWithPath: "/dev/null")
    var haveLog = false
    var csvPath:URL = URL.init(fileURLWithPath: "/dev/null")
    var haveCsv = false
    

    func log(_ message:String) {
        if (useOSConsoleLog) {
            os_log("%@", log: .default, type: .info, message)
        }
        if (saveDebugLog && haveLog) {
            do {
                let fileHandle = try FileHandle(forWritingTo: logPath)
                let data = message.data(using: String.Encoding.utf8, allowLossyConversion: true)!
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } catch {
                self.log_error("Error appending to log \(self.logPath.absoluteString)")
            }
        }
    }
    func log_debug(_ message:String) {
        if (useOSConsoleLog) {
            os_log("%@", log: .default, type: .debug, message)
        }
        if (saveDebugLog && haveLog) {
            do {
                let fileHandle = try FileHandle(forWritingTo: logPath)
                let data = message.data(using: String.Encoding.utf8, allowLossyConversion: true)!
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } catch {
                self.log_error("Error appending to log \(self.logPath.absoluteString)")
            }
        }
    }
    func log_error(_ message:String) {
        if (useOSConsoleLog) {
            os_log("%@", log: .default, type: .error, message)
        }
        if (saveDebugLog && haveLog) {
            do {
                let fileHandle = try FileHandle(forWritingTo: logPath)
                let data = message.data(using: String.Encoding.utf8, allowLossyConversion: true)!
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } catch {
                os_log("Error appending to log", log: .default, type: .error)
            }
        }
    }
    func write_csv(_ csvLine:String) {
        if (haveCsv) {
            do {
                let fileHandle = try FileHandle(forWritingTo: csvPath)
                let data = csvLine.data(using: String.Encoding.utf8, allowLossyConversion: true)!
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } catch {
                self.log_error("Error appending to csv: `\(self.csvPath.absoluteString)`")
            }
        } else {
            self.log_error("Tried to write CSV line, but `haveCsv` is false.")
        }
    }
    
    
    override init() {
        super.init()

        let path = try? FileManager.default.url(for: .documentDirectory, in: .allDomainsMask, appropriateFor: nil, create: false)
        if (path != nil) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "y-MM-dd'T'HHmmss"
            let nowStr = dateFormatter.string(from: Date.init())
            let csv_fn = "data-\(nowStr).csv"
            csvPath = path!.appendingPathComponent(csv_fn)
            haveCsv = true

            if (saveDebugLog) {
                let log_fn = "log-\(nowStr).txt"
                logPath = path!.appendingPathComponent(log_fn)
                haveLog = true
            }

            do {
                try latestRow.write(to: self.csvPath, atomically: true, encoding: .utf8)
            } catch {
                self.log_error("Error writing to csv: \(self.csvPath.absoluteString)")
            }
        }

        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        
        locationManager.startUpdatingLocation()
        locationManager.delegate = self
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
    }
    
    func newData() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd'T'HH:mm:ss.SSSZZZ"
        let timeStr = dateFormatter.string(from: latestUpdate)
        
        let lat = self.latestLoc.coordinate.latitude
        let lon = self.latestLoc.coordinate.longitude
        let h_acc = self.latestLoc.horizontalAccuracy
        let elevation = self.latestLoc.altitude
        let elevation_acc = self.latestLoc.verticalAccuracy
        let vel = self.latestLoc.speed
        let vel_acc = self.latestLoc.speedAccuracy
        let course = self.latestLoc.course
        let course_acc = self.latestLoc.courseAccuracy
        
        // http://www.kylesconverter.com/speed-or-velocity/meters-per-second-to-miles-per-hour
        let f_lat = String(format: "%.4f", lat)
        let f_lon = String(format: "%.4f", lon)
        let f_ele_ft = String(format: "%.1f", (elevation * 3.280839895013123))
        let f_ele_acc = String(format: "%.1f", (elevation_acc * 3.280839895013123))
        let f_vel_mph = String(format: "%.1f", (vel * 2.2369362920544025))
        let f_vel_acc = String(format: "%.1f", (vel_acc * 2.2369362920544025))
        let f_course = String(format: "%.1f", course)
        
        let f_h_acc = String(format: "%d", Int(h_acc))
        let f_course_acc = String(format: "%.1f", course_acc)

        
        var vel_course_csv = ""
        var vel_course_screen = ""
        if (vel != -1.0) {
            vel_course_screen = "\n\nSpeed: \(f_vel_mph) mph (+/- \(f_vel_acc) mph)\nCourse: \(f_course)º (+/- \(f_course_acc)º)"
            
            vel_course_csv = ",\(vel),\(vel_acc),\(course),\(course_acc)"
        } else {
            vel_course_csv = ",,,,"
        }
        
        latestRow = "\(timeStr),\(lat),\(lon),\(h_acc),\(elevation),\(elevation_acc)\(vel_course_csv)"
        screenText = "\(timeStr)\n\n\(f_lat), \(f_lon) (+/- \(f_h_acc) m)\nElevation: \(f_ele_ft) ft (+/- \(f_ele_acc) ft)\(vel_course_screen)\n\n"
        
        for index in 0...3 {
            var tpms_pressure = ""
            var tpms_temperature = ""
            var tpms_pressure_screen = ""
            var tpms_temperature_screen = ""
            var haveVal = false
            if (tpms_pressure_kpa[index] >= 50.0) && (tpms_pressure_kpa[index] < 300.0) {
                tpms_pressure = String(format: "%.4f", tpms_pressure_kpa[index])
                tpms_pressure_screen = String(format: "%.4f psi", (tpms_pressure_kpa[index] * 0.14503773779))
                haveVal = true
            } else if (tpms_pressure_kpa_persist[index] >= 50.0) && (tpms_pressure_kpa_persist[index] < 300.0) {
                tpms_pressure_screen = String(format: "(%.4f psi)", (tpms_pressure_kpa_persist[index] * 0.14503773779))
                haveVal = true
            }
            if (tpms_temperature_c[index] != 0.0) {
                tpms_temperature = String(format: "%.4f", tpms_temperature_c[index])
                tpms_temperature_screen = String(format: "%.4f ºF", ((tpms_temperature_c[index] * 9/5) + 32))
                haveVal = true
            } else if (tpms_temperature_c_persist[index] != 0.0) {
                tpms_temperature_screen = String(format: "(%.4f ºF)", ((tpms_temperature_c_persist[index] * 9/5) + 32))
                haveVal = true
            }
            let secSinceLastTick:Double = abs(tpms_last_tick[index].timeIntervalSinceNow)
            var f_sec = ""
            if (haveVal) {
                f_sec = String(format: "       (%.1f ago)\n", secSinceLastTick)
            }
            latestRow += ",\(tpms_pressure),\(tpms_temperature)"
            screenText += "TPMS\(index+1): \(tpms_pressure_screen)\n       \(tpms_temperature_screen)\n\(f_sec)"
        }
        latestRow += "\n"
        
        self.log_debug("\(self.latestRow)")
        self.write_csv(latestRow)


        tpms_pressure_kpa = [0.0, 0.0, 0.0, 0.0]
        tpms_temperature_c = [0.0, 0.0, 0.0, 0.0]

        if ((centralManager.state == .poweredOn) && !centralManager.isScanning) {
            centralManager.scanForPeripherals(withServices: [tpmsServiceCBUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
}


extension DataDelegate: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        latestLoc = locations[0]
        latestUpdate = Date.init()
        self.newData()
    }
}





extension DataDelegate: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .resetting:
            self.log_debug("central.state is .resetting")
        case .unsupported:
            self.log_debug("central.state is .unsupported")
        case .unauthorized:
            self.log_debug("central.state is .unauthorized")
        case .poweredOff:
            self.log_debug("central.state is .poweredOff")
        case .poweredOn:
            self.log_debug("central.state is .poweredOn")
            centralManager.scanForPeripherals(withServices: [tpmsServiceCBUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        case .unknown:
            self.log("central.state is .unknown")
        default:
            self.log("unhandled central state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        var name = ""
        if (peripheral.name != nil) {
            name = peripheral.name!
        }
        var s = "\nADVERTISEMENT FOUND:\n\(name):\t\(peripheral.identifier)\n"
        s += "CBAdvertisementDataLocalNameKey: \(advertisementData[CBAdvertisementDataLocalNameKey] ?? "none")\n"
        s += "CBAdvertisementDataManufacturerDataKey: \(advertisementData[CBAdvertisementDataManufacturerDataKey] ?? "none")\n"
        
        s += "CBAdvertisementDataServiceDataKey: \(advertisementData[CBAdvertisementDataServiceDataKey] ?? "none")\n"
        s += "CBAdvertisementDataServiceUUIDsKey: \(advertisementData[CBAdvertisementDataServiceUUIDsKey] ?? "none")\n"
        s += "CBAdvertisementDataOverflowServiceUUIDsKey: \(advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] ?? "none")\n"
        s += "CBAdvertisementDataTxPowerLevelKey: \(advertisementData[CBAdvertisementDataTxPowerLevelKey] ?? "none")\n"
        s += "CBAdvertisementDataIsConnectable: \(advertisementData[CBAdvertisementDataIsConnectable] ?? "none")\n"
        s += "CBAdvertisementDataSolicitedServiceUUIDsKey: \(advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] ?? "none")\n"
        s += "\n=====\n\n"
        
        self.log_debug(s)
        
        // Per https://github.com/ricallinson/tpms/blob/c142138098c383e703635c2f6fb166a03134793c/sensor.go
        // bytes 8,9,10,11 / 1000 -> pressure in kpa
        // bytes 12,13,14,15 /100 -> temp in celsius
        let rawData:Data = advertisementData[CBAdvertisementDataManufacturerDataKey] as! Data
        let pressureRaw = rawData.subdata(in: Range(8...11))
//        let pressureConv1 = UInt32(littleEndian: pressureRaw.withUnsafeBytes( { $0.pointee } ) )
        let pressureConv:Double = pressureRaw.withUnsafeBytes { Double($0.load(as: UInt32.self)) } / 1000.0
        let temperatureRaw = rawData.subdata(in: Range(12...15))
        let temperatureConv:Double = temperatureRaw.withUnsafeBytes { Double($0.load(as: UInt32.self)) } / 100.0

        var idx:Int = -1
        if (name.starts(with: "TPMS1")) {
            idx = 0
        } else if (name.starts(with: "TPMS2")) {
            idx = 1
        } else if (name.starts(with: "TPMS3")) {
            idx = 2
        } else if (name.starts(with: "TPMS4")) {
            idx = 3
        }

        if (idx != -1) {
            let haveGoodTick = ((pressureConv != 0.0) || (temperatureConv != 0.0))
            if (haveGoodTick) {
                tpms_pressure_kpa[idx] = pressureConv
                tpms_temperature_c[idx] = temperatureConv
                if pressureConv != 0.0 {
                    tpms_pressure_kpa_persist[idx] = pressureConv
                }
                if temperatureConv != 0.0 {
                    tpms_temperature_c_persist[idx] = temperatureConv
                }
                latestUpdate = Date()
                tpms_last_tick[idx] = Date()
            
                self.newData()
            }
        }
    }
}
