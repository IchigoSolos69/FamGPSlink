import Flutter
import UIKit
import CoreLocation
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var tracker: FamilyLocationTracker?
  private var locationChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil,
       Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
      FirebaseApp.configure()
    }
    if FirebaseApp.app() != nil {
      tracker = FamilyLocationTracker()
      tracker?.restore()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    locationChannel = FlutterMethodChannel(name: "com.famgpslink/location", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    locationChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if self.tracker == nil && FirebaseApp.app() != nil { self.tracker = FamilyLocationTracker() }
      guard let tracker = self.tracker else {
        result(FlutterError(code: "setup", message: "This build needs family configuration.", details: nil)); return
      }
      tracker.handle(call, result: result)
    }
  }
}

/// Native location delivery and uploads do not depend on a running Dart isolate.
final class FamilyLocationTracker: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private let preferences = UserDefaults.standard
  private var observers: [(DatabaseReference, DatabaseHandle)] = []
  private var authObserver: AuthStateDidChangeListenerHandle?
  private var state: DatabaseReference?
  private var memberID = ""
  private var uid = ""
  private var revision: Int64 = -1
  private var sharing = false
  private var overridden = true
  private var connected = false
  private var uploading = false
  private var pending: [String: Any]?
  private var retry: Timer?
  private var idle: Timer?
  private var retrySeconds: Double = 5
  private var anchor: CLLocation?
  private var permissionReply: FlutterResult?
  private var fixRequest: FreshLocationRequest?
  private var collecting = false
  private var moving = true
  private var uploadTimer: Timer?
  private var lastUploadAt: TimeInterval = 0
  private var generation = 0

  override init() {
    super.init()
    manager.delegate = self
    manager.activityType = .other
    manager.pausesLocationUpdatesAutomatically = true
    manager.distanceFilter = 50
    manager.desiredAccuracy = kCLLocationAccuracyBest
  }

  func restore() {
    if preferences.bool(forKey: "trackingWanted"), let id = preferences.string(forKey: "memberID") {
      start(id)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      let authorization = manager.authorizationStatus
      result(["foreground": authorization == .authorizedAlways || authorization == .authorizedWhenInUse,
        "background": authorization == .authorizedAlways, "precise": manager.accuracyAuthorization == .fullAccuracy,
        "gpsEnabled": CLLocationManager.locationServicesEnabled(), "powerSave": ProcessInfo.processInfo.isLowPowerModeEnabled,
        "lastError": preferences.string(forKey: "lastError") ?? ""])
    case "requestForeground":
      if manager.authorizationStatus == .notDetermined {
        if permissionReply != nil { result(FlutterError(code: "busy", message: "A permission request is already open.", details: nil)); return }
        permissionReply = result
        manager.requestWhenInUseAuthorization()
      } else { result(nil) }
    case "requestBackground": manager.requestAlwaysAuthorization(); result(nil)
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
      result(nil)
    case "start":
      guard let arguments = call.arguments as? [String: Any], let id = arguments["memberId"] as? String else {
        result(FlutterError(code: "setup", message: "Profile is not configured.", details: nil)); return
      }
      let authorization = manager.authorizationStatus
      guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
        result(FlutterError(code: "permission", message: "Allow location access before sharing.", details: nil)); return
      }
      start(id); result(nil)
    case "stop": stop(clearPending: true); preferences.set(false, forKey: "trackingWanted"); result(nil)
    case "freshFix":
      if fixRequest != nil { result(FlutterError(code: "busy", message: "Already requesting a fresh location.", details: nil)); return }
      fixRequest = FreshLocationRequest { [weak self] fix, error in
        self?.fixRequest = nil
        if let fix = fix {
          result(["latitude": fix.coordinate.latitude, "longitude": fix.coordinate.longitude,
            "accuracy": fix.horizontalAccuracy, "measuredAt": Int64(fix.timestamp.timeIntervalSince1970 * 1000)])
        } else { result(FlutterError(code: "location", message: error ?? "No fresh GPS fix. Your manual pin remains active.", details: nil)) }
      }
      fixRequest?.begin()
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func start(_ id: String) {
    guard let user = Auth.auth().currentUser else { return }
    if memberID == id && uid == user.uid && !observers.isEmpty { return }
    stop(clearPending: false)
    memberID = id
    uid = user.uid
    preferences.set(id, forKey: "memberID")
    preferences.set(true, forKey: "trackingWanted")
    state = Database.database().reference(withPath: "family/states/\(id)")
    pending = LatestFixKeychain.read()
    if pending?["uid"] as? String != uid || pending?["memberID"] as? String != memberID {
      pending = nil; LatestFixKeychain.clear()
    }
    let sessionGeneration = generation
    authObserver = Auth.auth().addStateDidChangeListener { [weak self] _, user in
      guard let self = self else { return }
      guard self.generation == sessionGeneration else { return }
      if user?.uid != self.uid { self.halt("Device authentication changed.") }
    }
    observe(Database.database().reference(withPath: "family/members/\(id)")) { [weak self] snapshot in
      guard let self = self else { return }
      if snapshot.childSnapshot(forPath: "authUid").value as? String != self.uid || snapshot.childSnapshot(forPath: "active").value as? Bool != true {
        self.halt("This phone needs owner approval again.")
      }
    }
    observe(state!.child("control")) { [weak self] snapshot in
      guard let self = self else { return }
      self.sharing = snapshot.childSnapshot(forPath: "sharingEnabled").value as? Bool == true
      self.overridden = snapshot.childSnapshot(forPath: "overrideActive").value as? Bool != false
      let next = (snapshot.childSnapshot(forPath: "revision").value as? NSNumber)?.int64Value ?? -1
      if self.revision != next {
        self.revision = next
        if (self.pending?["revision"] as? NSNumber)?.int64Value != next { self.pending = nil; LatestFixKeychain.clear() }
      }
      if !self.sharing || self.overridden { self.halt("") }
      else { self.collect(); self.flush() }
    }
    observe(Database.database().reference(withPath: ".info/connected")) { [weak self] snapshot in
      guard let self = self else { return }
      self.connected = snapshot.value as? Bool == true
      if self.connected { self.retrySeconds = 5; self.flush() }
    }
  }

  private func observe(_ reference: DatabaseReference, change: @escaping (DataSnapshot) -> Void) {
    let observationGeneration = generation
    let handle = reference.observe(.value, with: { [weak self] snapshot in
      guard let self = self, self.generation == observationGeneration else { return }
      change(snapshot)
    }, withCancel: { [weak self] _ in
      guard let self = self, self.generation == observationGeneration else { return }
      self.halt("Location service is unavailable or device access was revoked.")
    })
    observers.append((reference, handle))
  }

  private func collect() {
    guard sharing && !overridden && !collecting else { return }
    collecting = true
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    manager.startUpdatingLocation()
    if CLLocationManager.significantLocationChangeMonitoringAvailable() { manager.startMonitoringSignificantLocationChanges() }
    scheduleIdle()
  }

  private func scheduleIdle() {
    idle?.invalidate()
    idle = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
      // Core Location may pause completely while stationary. Significant-change
      // monitoring resumes movement without a perpetual high-accuracy GPS loop.
      self?.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
      self?.moving = false
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard sharing && !overridden, let fix = locations.last, fix.horizontalAccuracy >= 0,
      abs(fix.timestamp.timeIntervalSinceNow) <= 60 else { return }
    if fix.speed >= 0.8 || anchor == nil || fix.distance(from: anchor!) >= 50 {
      moving = true
      anchor = fix
      self.manager.desiredAccuracy = ProcessInfo.processInfo.isLowPowerModeEnabled ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyBest
      self.manager.startUpdatingLocation()
      scheduleIdle()
    }
    let measuredAt = Int64(fix.timestamp.timeIntervalSince1970 * 1000)
    if let previous = (pending?["measuredAt"] as? NSNumber)?.int64Value, measuredAt <= previous { return }
    pending = ["latitude": fix.coordinate.latitude, "longitude": fix.coordinate.longitude,
      "accuracy": fix.horizontalAccuracy, "measuredAt": measuredAt, "revision": revision,
      "uid": uid, "memberID": memberID]
    LatestFixKeychain.save(pending!)
    flush()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let authorization = manager.authorizationStatus
    if authorization != .notDetermined { permissionReply?(nil); permissionReply = nil }
    if authorization == .denied || authorization == .restricted { halt("Allow location access to resume sharing.") }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if let error = error as? CLError, error.code == .denied { halt("Location permission is unavailable.") }
    else { preferences.set("Waiting for a usable location fix.", forKey: "lastError") }
  }

  private func flush() {
    guard connected && !uploading && sharing && !overridden, let fix = pending, let state = state else { return }
    guard (fix["revision"] as? NSNumber)?.int64Value == revision, fix["uid"] as? String == uid else {
      pending = nil; LatestFixKeychain.clear(); return
    }
    let interval: TimeInterval = moving ? 60 : 300
    let wait = interval - (Date().timeIntervalSince1970 - lastUploadAt)
    if wait > 0 {
      uploadTimer?.invalidate()
      uploadTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in self?.flush() }
      return
    }
    let uploadGeneration = generation
    uploading = true
    state.runTransactionBlock({ data in
      guard var current = data.value as? [String: Any] else { return TransactionResult.success(withValue: data) }
      guard let control = current["control"] as? [String: Any], control["sharingEnabled"] as? Bool == true,
        control["overrideActive"] as? Bool == false,
        (control["revision"] as? NSNumber)?.int64Value == (fix["revision"] as? NSNumber)?.int64Value else { return TransactionResult.abort() }
      let previous = (current["location"] as? [String: Any])?["measuredAt"] as? NSNumber
      let measuredAt = (fix["measuredAt"] as? NSNumber)?.int64Value ?? 0
      if measuredAt <= (previous?.int64Value ?? 0) { return TransactionResult.abort() }
      current["location"] = ["latitude": fix["latitude"]!, "longitude": fix["longitude"]!,
        "accuracy": fix["accuracy"]!, "measuredAt": measuredAt, "publishedAt": ServerValue.timestamp()]
      data.value = current
      return TransactionResult.success(withValue: data)
    }, andCompletionBlock: { [weak self] error, _, _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        guard self.generation == uploadGeneration else { return }
        self.uploading = false
        if let error = error as NSError? {
          // Firebase RTDB's public API exposes NSError; FUtilities maps
          // permission_denied to code 1 in the FirebaseDatabase domain.
          if error.domain == "com.firebase" && error.code == 1 { self.halt("Location upload denied. Check device approval and phone time."); return }
          self.preferences.set("Location upload unavailable; retaining the latest fix.", forKey: "lastError")
          self.retry?.invalidate()
          self.retry = Timer.scheduledTimer(withTimeInterval: self.retrySeconds, repeats: false) { [weak self] _ in self?.flush() }
          self.retrySeconds = min(300, self.retrySeconds * 2)
        } else {
          self.lastUploadAt = Date().timeIntervalSince1970
          if (self.pending?["measuredAt"] as? NSNumber)?.int64Value == (fix["measuredAt"] as? NSNumber)?.int64Value {
            self.pending = nil; LatestFixKeychain.clear()
          }
          self.preferences.set("", forKey: "lastError")
          self.retrySeconds = 5
          self.flush()
        }
      }
    }, withLocalEvents: false)
  }

  private func halt(_ message: String) {
    preferences.set(message, forKey: "lastError")
    preferences.set(false, forKey: "trackingWanted")
    stop(clearPending: true)
  }

  private func stop(clearPending: Bool) {
    generation += 1
    uploading = false
    manager.stopUpdatingLocation()
    manager.stopMonitoringSignificantLocationChanges()
    collecting = false
    idle?.invalidate(); retry?.invalidate(); uploadTimer?.invalidate()
    for (reference, handle) in observers { reference.removeObserver(withHandle: handle) }
    observers.removeAll()
    if let observer = authObserver { Auth.auth().removeStateDidChangeListener(observer) }
    authObserver = nil
    connected = false
    sharing = false
    overridden = true
    memberID = ""
    if clearPending { pending = nil; LatestFixKeychain.clear() }
  }
}

final class FreshLocationRequest: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var timer: Timer?
  private var completion: ((CLLocation?, String?) -> Void)?
  init(completion: @escaping (CLLocation?, String?) -> Void) { self.completion = completion; super.init(); manager.delegate = self }
  func begin() {
    guard CLLocationManager.locationServicesEnabled(), manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
      finish(nil, "Enable location services and allow location access. Your manual pin remains active."); return
    }
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
    manager.startUpdatingLocation()
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
      self?.finish(nil, "No fresh GPS fix. Your manual pin remains active.")
    }
  }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    if let fix = locations.last, fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSinceNow) <= 5 {
      finish(fix, nil)
    }
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if let error = error as? CLError, error.code == .denied { finish(nil, "Allow location permission. Your manual pin remains active.") }
  }
  private func finish(_ fix: CLLocation?, _ message: String?) {
    manager.stopUpdatingLocation(); timer?.invalidate()
    let reply = completion; completion = nil; reply?(fix, message)
  }
}

enum LatestFixKeychain {
  private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.famgpslink.latest-fix", kSecAttrAccount as String: "pending"] }
  static func save(_ fix: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: fix) else { return }
    clear()
    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(attributes as CFDictionary, nil)
  }
  static func read() -> [String: Any]? {
    var attributes = query
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
  static func clear() { SecItemDelete(query as CFDictionary) }
}
