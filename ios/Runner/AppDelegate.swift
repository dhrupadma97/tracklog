import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String ?? ""
    GMSServices.provideAPIKey(mapsApiKey)
    GeneratedPluginRegistrant.register(with: self)

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let diagnosticsChannel = FlutterMethodChannel(name: "com.example.tracklog/diagnostics",
                                                  binaryMessenger: controller.binaryMessenger)
    diagnosticsChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "getMapsKeyStatus" {
        let key = mapsApiKey
        result([
          "keyLength": key.count,
          "isEmpty": key.isEmpty,
          "prefix": String(key.prefix(6)),
          "isValid": key.count > 20
        ])
      } else if call.method == "getMapsApiKey" {
        result(mapsApiKey)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
