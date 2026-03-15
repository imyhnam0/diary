import Flutter
import FirebaseCore
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let widgetChannelName = "diary/home_widget"
  private let appGroupId = "group.com.imyhnam.diary"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: widgetChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate unavailable", details: nil))
          return
        }
        guard let defaults = UserDefaults(suiteName: self.appGroupId) else {
          result(FlutterError(code: "APP_GROUP_ERROR", message: "Failed to open app group", details: nil))
          return
        }
        switch call.method {
        case "updateDiaryWidget":
          guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "BAD_ARGS", message: "Expected payload dictionary", details: nil))
            return
          }
          let today = (args["today"] as? String) ?? ""
          let todayImage = (args["todayImage"] as? String) ?? ""
          let yesterday = (args["yesterday"] as? String) ?? ""
          let yesterdayImage = (args["yesterdayImage"] as? String) ?? ""
          let recent = (args["recent"] as? [String]) ?? []
          let recentImages = (args["recentImages"] as? [String]) ?? []
          let month = (args["month"] as? String) ?? ""
          let monthMap = (args["monthMap"] as? [String: String]) ?? [:]
          let monthMapPhotos = (args["monthMapPhotos"] as? [String: String]) ?? [:]
          let monthMapTitles = (args["monthMapTitles"] as? [String: String]) ?? [:]
          defaults.set(today, forKey: "widget_today_emoji")
          defaults.set(todayImage, forKey: "widget_today_image_base64")
          defaults.set(yesterday, forKey: "widget_yesterday_emoji")
          defaults.set(yesterdayImage, forKey: "widget_yesterday_image_base64")
          defaults.set(recent, forKey: "widget_recent_emojis")
          defaults.set(recentImages, forKey: "widget_recent_images")
          defaults.set(month, forKey: "widget_month_key")
          defaults.set(monthMap, forKey: "widget_month_map")
          defaults.set(monthMapPhotos, forKey: "widget_month_map_photos")
          defaults.set(monthMapTitles, forKey: "widget_month_map_titles")
        case "syncWidgetLanguage":
          let args = call.arguments as? [String: Any]
          let language = (args?["language"] as? String) ?? "ko"
          defaults.set(language, forKey: "widget_language")
        default:
          result(FlutterMethodNotImplemented)
          return
        }
        defaults.set(Date().timeIntervalSince1970, forKey: "widget_updated_at")
        defaults.synchronize()
        if #available(iOS 14.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
        }
        result(nil)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
