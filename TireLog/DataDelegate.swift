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

let csvHeader:String = "timestamp," +
    "lat,lon,latlon_acc_m,latlon_acc_ft," +
    "elevation_m,elevation_acc_m,elevation_ft,elevation_acc_ft," +
    "speed_mps,speed_acc_mps,speed_mph,speed_acc_mph," +
    "have_tire," +
    "tire_fl_kpa,tire_fl_psi,tire_fl_c,tire_fl_f," +
    "tire_fr_kpa,tire_fr_psi,tire_fr_c,tire_fr_f," +
    "tire_rl_kpa,tire_rl_psi,tire_rl_c,tire_rl_f," +
    "tire_rr_kpa,tire_rr_psi,tire_rr_c,tire_rr_f" +
    "\n"

class DataDelegate:NSObject,ObservableObject {
    @Published var latestRow: String = csvHeader
    
    @Published var screenText: String = "..."
    @Published var screenTire1Temp: String = "..."
    @Published var screenTire1Pres: String = "..."
    @Published var screenTire1Time: String = "..."
    @Published var screenTire2Temp: String = "..."
    @Published var screenTire2Pres: String = "..."
    @Published var screenTire2Time: String = "..."
    @Published var screenTire3Temp: String = "..."
    @Published var screenTire3Pres: String = "..."
    @Published var screenTire3Time: String = "..."
    @Published var screenTire4Temp: String = "..."
    @Published var screenTire4Pres: String = "..."
    @Published var screenTire4Time: String = "..."
    
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
    
    var didStartCsv = false
    var didGetTireData = false
    

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
    func init_csv() {
        do {
            try csvHeader.write(to: self.csvPath, atomically: true, encoding: .utf8)
        } catch {
            self.log_error("Error writing to csv: \(self.csvPath.absoluteString)")
        }
    }
    func write_csv(_ csvLine:String) {
        if (haveCsv) {
            if (!didStartCsv) {
                init_csv()
                didStartCsv = true
            }
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
        }

        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        
        locationManager.startUpdatingLocation()
        locationManager.delegate = self
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        //Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { (t) in
        //    self.newData()
        //}
    }
    
    func newData() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd'T'HH:mm:ss.SSSZZZ"
        let timeStr = dateFormatter.string(from: latestUpdate)
        
        let lat = self.latestLoc.coordinate.latitude
        let lon = self.latestLoc.coordinate.longitude
        let latlon_acc = self.latestLoc.horizontalAccuracy
        let elevation = self.latestLoc.altitude
        let elevation_acc = self.latestLoc.verticalAccuracy
        var vel = self.latestLoc.speed
        var vel_acc = self.latestLoc.speedAccuracy
        
        if (vel < 0) {
            vel = 0
        }
        if (vel_acc < 0) {
            vel_acc = 0
        }

        // http://www.kylesconverter.com/speed-or-velocity/meters-per-second-to-miles-per-hour
        
        let c_latlon_acc_ft = latlon_acc * 3.280839895013123
        let c_elevation_ft = elevation * 3.280839895013123
        let c_elevation_ft_acc = elevation_acc * 3.280839895013123
        let c_vel_mph = vel * 2.2369362920544025
        let c_vel_mph_acc = vel_acc * 2.2369362920544025

        let f_lat = String(format: "%.4f", lat)
        let f_lon = String(format: "%.4f", lon)
        
        let f_ele_ft = String(format: "%.1f", c_elevation_ft)
        let f_ele_ft_acc = String(format: "%.1f", c_elevation_ft_acc)
        let f_vel_mph = String(format: "%.1f", c_vel_mph)
        let f_vel_mph_acc = String(format: "%.1f", c_vel_mph_acc)
        
        // let f_latlon_acc = String(format: "%d", Int(latlon_acc))
        let f_latlon_acc_ft = String(format: "%d", Int(c_latlon_acc_ft))

        latestRow = "\(timeStr),\(lat),\(lon),\(latlon_acc),\(c_latlon_acc_ft),\(elevation),\(elevation_acc),\(c_elevation_ft),\(c_elevation_ft_acc),\(vel),\(vel_acc),\(c_vel_mph),\(c_vel_mph_acc)"
        
        screenText = "\(timeStr)\n\(f_lat), \(f_lon) (± \(f_latlon_acc_ft) ft)\n@ \(f_ele_ft) ft (± \(f_ele_ft_acc))\n\n\(f_vel_mph) mph (± \(f_vel_mph_acc))\n\n"
        
        var haveTire = "0"
        for index in 0...3 {
            let pressure_kpa = tpms_pressure_kpa[index]
            let temperature_c = tpms_temperature_c[index]
            if (pressure_kpa >= 50.0) && (pressure_kpa < 300.0) {
                haveTire = "1"
            }
            if (temperature_c != 0.0) {
                haveTire = "1"
            }
        }
        latestRow += ",\(haveTire)"

        for index in 0...3 {
//            let pressure_kpa = Double.random(in: 100.0 ..< 300.0)
            let pressure_kpa = tpms_pressure_kpa[index]
            let pressure_kpa_persist = tpms_pressure_kpa_persist[index]
            let pressure_psi = (pressure_kpa * 0.14503773779)
            let pressure_psi_persist = (pressure_kpa_persist * 0.14503773779)
            let temperature_c = tpms_temperature_c[index]
//            let temperature_c = Double.random(in: 15.0 ..< 40.0)
            let temperature_c_persist = tpms_temperature_c_persist[index]
            let temperature_f = ((temperature_c * 9/5) + 32)
            let temperature_f_persist = ((temperature_c_persist * 9/5) + 32)

            var f_pressure_kpa = ""
            var f_pressure_psi = ""
            var f_temperature_c = ""
            var f_temperature_f = ""
            
            var f_pressure_psi_screen = ""
            var f_temperature_f_screen = ""
            
            let formatPsi = NumberFormatter()
            formatPsi.minimumFractionDigits = 2
            formatPsi.maximumFractionDigits = 2
            let formatFahrenheit = NumberFormatter()
            formatFahrenheit.minimumFractionDigits = 1
            formatFahrenheit.maximumFractionDigits = 1
            let formatSeconds = NumberFormatter()
            formatSeconds.minimumFractionDigits = 1
            formatSeconds.maximumFractionDigits = 1
            
            var haveVal = false
            // If we have a valid pressure
            if (pressure_kpa >= 50.0) && (pressure_kpa < 300.0) {
                f_pressure_kpa = String(format: "%.4f", pressure_kpa)
                f_pressure_psi = String(format: "%.4f", pressure_psi)
                f_pressure_psi_screen = String(format:"%.2f", pressure_psi).padding(toLength: 5, withPad: " ", startingAt: 0)
                haveVal = true
            } else if (pressure_kpa_persist >= 50.0) && (pressure_kpa_persist < 300.0) {
                f_pressure_psi_screen = String(format:"%.2f", pressure_psi_persist).padding(toLength: 5, withPad: " ", startingAt: 0)
                haveVal = true
            } else {
                f_pressure_psi_screen = "--.--"
            }
            if (temperature_c != 0.0) {
                f_temperature_c = String(format: "%.4f", temperature_c)
                f_temperature_f = String(format: "%.4f", temperature_f)
                f_temperature_f_screen = String(format:"%.1f", temperature_f).padding(toLength: 5, withPad: " ", startingAt: 0)
                haveVal = true
            } else if (temperature_c_persist != 0.0) {
                f_temperature_f_screen = String(format:"%.1f", temperature_f_persist).padding(toLength: 5, withPad: " ", startingAt: 0)
                haveVal = true
            } else {
                f_temperature_f_screen = "---.-"
            }
            let secSinceLastTick:Double = abs(tpms_last_tick[index].timeIntervalSinceNow)
//            let secSinceLastTick = Double.random(in: 0.0 ..< 1000.0)
            var f_sec_screen = ""
            if (haveVal) {
                f_sec_screen = String(format:"%.1f", secSinceLastTick).padding(toLength: 6, withPad: " ", startingAt: 0)
            } else {
                f_sec_screen = "----.-"
            }
            
            latestRow += ",\(f_pressure_kpa),\(f_pressure_psi),\(f_temperature_c),\(f_temperature_f)"
            switch index {
            case 0:
                screenTire1Temp = f_temperature_f_screen
                screenTire1Pres = f_pressure_psi_screen
                screenTire1Time = f_sec_screen
            case 1:
                screenTire2Temp = f_temperature_f_screen
                screenTire2Pres = f_pressure_psi_screen
                screenTire2Time = f_sec_screen
            case 2:
                screenTire3Temp = f_temperature_f_screen
                screenTire3Pres = f_pressure_psi_screen
                screenTire3Time = f_sec_screen
            case 3:
                screenTire4Temp = f_temperature_f_screen
                screenTire4Pres = f_pressure_psi_screen
                screenTire4Time = f_sec_screen
            default:
                continue
            }
        }
        latestRow += "\n"
        
        self.log_debug("\(self.latestRow)")
        if (didGetTireData) {
            self.write_csv(latestRow)
        }

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
                didGetTireData = true
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
