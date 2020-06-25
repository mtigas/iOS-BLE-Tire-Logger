# iOS TPMS Data Logger (for BLE tire pressure sensors, inc. "TP630", "ZEEPIN", etc)

&copy; 2020, [Mike Tigas](https://mike.tig.as/)  
Please see the [LICENSE.txt](LICENSE.txt) file for usage and redistribution terms.

---

A tiny utility for _super cheap_ BLE tire pressure/temperature sensors available on the internet. Most of these products do have their own apps (i.e. [this one](https://apps.apple.com/us/app/tpmsii/id1436006976)) which don't have features beyond displaying the values (in various units) and providing bounds alerts (for low air pressure, etc) while the app is open.

I wanted something to use alongside [RaceChrono](https://racechrono.com/) which I am currently using as a data logger with dash cam footage, particularly when [putting together video from autocross and similar events](https://www.youtube.com/playlist?list=PLRa9P6UDYxmqmdjMVgHUMYNy2yOgHtS_r) in [RaceRender](http://racerender.com/Products/index.html).

[![Example video render of a car on an autocross track, with a cone obstacle course, and an overlay of car data including speed and RPM](https://github.com/mtigas/ios-ble-tpms-logger/blob/main/doc/screenshot-video.jpg?raw=true)](https://www.youtube.com/watch?v=rZGtBeNl4KU&list=PLRa9P6UDYxmqmdjMVgHUMYNy2yOgHtS_r&index=2)  
(TODO: screenshot of video that actually uses the tire data collected by this utility)

---

This app looks for BLE sensors that advertise the `0xFBB0` service. See **Device details** below for some example devices. These devices usually advertise a name that looks like `TPMS1_1ABC23`, where the number `1` is something from `1`-`4`.

Any sensor starting with `TPMS1_` is assumed to be the front-left tire, `TPMS2_` front-right, `TPMS3_` rear-left, and `TPMS4_` rear-right. (So as-is, this logger will definitely pick up interfering datapoints if another car has similar sensors.)

Data is saved as a CSV to the app's `documentDirectory`, and is accessible in the iOS Files app or in the Files section of the iOS device sync screen of MacOS: `On My iPhone/BLE Tire Logger/data-YYY-MM-DDTHHMMSS.csv`

See [doc/example-2020-06-24T234645.csv](doc/example-2020-06-24T234645.csv).

![Example CSV output](https://github.com/mtigas/ios-ble-tpms-logger/blob/main/doc/screenshot-csv.png?raw=true)


### Device details

* I personally ordered [this one](https://www.aliexpress.com/item/4000319184474.html) which unfortunately no longer seems to be available. I got the "external" one, which replaces the valve stem cap. (Total cost was $36.61 including tax, with free ePacket shipping that took about seven weeks to arrive to the USA.)
* This [ricallinson/tpms](https://github.com/ricallinson/tpms) project links over to [this "ZEEPIN TPMS Sensor Bluetooth Low Energy Tire Pressure Monitoring System"](https://smile.amazon.com/gp/product/B079JXMM2P/).
* I have seen a few other [posts around the internet](https://raspberrypi.stackexchange.com/questions/76959/how-to-decode-tpms-sensor-data-through-rpi3-bluetooth) refer to these as "TP630".

Using the free [nRF Connect app](https://www.nordicsemi.com/Software-and-tools/Development-Tools/nRF-Connect-for-mobile), raw information from the installed sensors can be seen here:

![nRF Connect output, showing raw Bluetooth LE data coming from the TPMS sensors installed on my car. MAC addresses, the BLE Service UUID "0xFBB0" and the "manufacturer data" are seen here.](https://github.com/mtigas/ios-ble-tpms-logger/blob/main/doc/screenshot-nrfconnect.png?raw=true)

In the package that I received, each sensor advertises a name of `TPMS{N}_{MMMMMM}`, where `{N}` is a one-digit index (`1`, `2`, `3`, `4`) and `{MMMMMM}` is a six hex character MAC address suffix (i.e. `3063F3`); upon closer examination, it looks like `N` is the first digit of `MMMMMM`. In the packaging, these indexes and IDs are provided on an index card with bar codes to be scanned by the [manufacturer's app](https://apps.apple.com/us/app/tpmsii/id1436006976). Per the packaging, `1` goes to front-left, `2` goes to front-right, `3` to rear-left, and `4` to rear-right; however, this does not seem to be an important distinction, since having the IDs means that we can keep track of these by ourself.

The devices advertise the [BLE Service ID](https://www.bluetooth.com/specifications/gatt/services/) `0xFBB0`. The devices cannot be connected or paired to and the devices do not receive any incoming BLE characteristics/packets/etc; all data is broadcast as part of the "Manufacturer data" portion of the BLE advertisement. In the above screenshot, that 16-byte manufacturer data (for sensor 3) looks like this (spaces added by me):

```
0x 83 EA CA 40 61 81 C8 1C 04 00 0B 0B 00 00 4B 00
```

I discovered [ricallinson/tpms](https://github.com/ricallinson/tpms), which contained excellent information on [extracting temperature and pressure](https://github.com/ricallinson/tpms/blob/master/sensor.go#L15-L20) from the BLE "manufacturer data" (`CBAdvertisementDataManufacturerDataKey`) part of the BLE advertisement. Bytes 8,9,10,11 are a representation of the air pressure in kPA, and bytes 12,13,14,15 represent the temperature in Celsius, both as little-endian 32bit unsigned integers that need some scale conversion; pseudocode:

```
pressure_kilopascal = Uint32(bytes[8:11])  / 1000
pressure_celsikus   = Uint32(bytes[12:15]) / 100
```

Checking this against the values in [manufacturer's app](https://apps.apple.com/us/app/tpmsii/id1436006976) suggests that this is is accurate.

### Output details

iOS' [CoreBluetooth](https://developer.apple.com/documentation/corebluetooth) is used to listen for the advertisement packets ([`CBCentralManager.scanForPeripherals(...)`](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/1518986-scanforperipherals)). The sensors do not stream data constantly, and because of the way BLE polling and advertising works (and because the sensors do not support being connected to or paired with), there is a chance that iOS may miss a given advertisement. As you can see in the example above, values for the sensors are only filled in when they are received; this codebase does not interpolate values between readings.

User [location](https://developer.apple.com/documentation/corelocation) is also requested with the [highest accuracy supported by the device](https://developer.apple.com/documentation/corelocation/kcllocationaccuracybestfornavigation). This is currently required to use the app

A CSV row is written any time there is _either_ a location update OR a new BLE advertisement received from a tire sensor.
