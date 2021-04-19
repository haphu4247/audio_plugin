import Flutter
import UIKit
import AVFoundation

public class SwiftAudioPlugin: NSObject, FlutterPlugin, AVAudioRecorderDelegate{
    var hasPermissions = false
    internal var isPaused = false
    internal var delegate: RecordingDelegate?
    internal var viewController: UIViewController?


    var audioRecorder: AVAudioRecorder!
    private var meterTimer:Timer!
    private var fileName:String!
    private var path: String?
    internal var recordingSession: AVAudioSession = AVAudioSession.sharedInstance()

    private let settings = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 2,
        AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue
    ]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "audio_plugin", binaryMessenger: registrar.messenger())
    let instance = SwiftAudioPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
        case "audios":
            print("audios")
            let audios = getAudios(call: call)
            result(audios)
        case "current":
            print("current")
            let recordingResult = getCurrent(call: call)
            result(recordingResult)
        case "stopRecording":
            let recordingResult = stopRecording(call: call)
            result(recordingResult)
            break
        case "startRecording":
            let recordingResult = startRecording(call: call)
            result(recordingResult)
            break
        case "setFileName":
            let dic = call.arguments as! [String:Any]
            let name = self.setFileName(fileName: dic["fileName"] as? String ?? "")
            result(name)
            break
        case "isRecording":
            if let audioRecorder = audioRecorder {
                result(audioRecorder.isRecording)
                print("isRecording=\(audioRecorder.isRecording)")
            }
            break
        case "hasPermissions":
            print("hasPermissions")
            switch AVAudioSession.sharedInstance().recordPermission{
            case .granted:
                print("granted")
                hasPermissions = true
                break
            case .denied:
                print("denied")
                hasPermissions = false
                break
            case .undetermined:
                print("undetermined")
                AVAudioSession.sharedInstance().requestRecordPermission() { [unowned self] allowed in
                    DispatchQueue.main.async {
                        if allowed {
                            self.hasPermissions = true
                        } else {
                            self.hasPermissions = false
                        }
                    }
                }
                break
            default:
                break
            }
            result(hasPermissions)
            break
        default:
            result("iOS " + UIDevice.current.systemVersion)
    }
  }

  func stopRecording(call: FlutterMethodCall) -> [String : Any]?{
      return self.finishRecording(call: call)
  }

  func getCurrent(call: FlutterMethodCall) -> [String : Any]?{
    if let audioRecorder = audioRecorder {
        let dic = call.arguments as? [String : Any]
        let channel = dic?["channel"] as? Int ?? 0

        audioRecorder.updateMeters()
        let duration = Int(audioRecorder.currentTime)
        var recordingResult = [String : Any]()
        recordingResult["path"] = path
        recordingResult["duration"] = duration
        recordingResult["peakPower"] = audioRecorder.peakPower(forChannel: channel)
        recordingResult["averagePower"] = audioRecorder.averagePower(forChannel: channel)
        recordingResult["isMeteringEnabled"] = audioRecorder.isMeteringEnabled
        recordingResult["isRecording"] = audioRecorder.isRecording
        return recordingResult
    }else{
        return nil
    }
  }

  func setFileName(fileName: String)->Bool{
      self.fileName = fileName
      return true
  }

  func startRecording(call: FlutterMethodCall) -> [String: Any]?{
      if(audioRecorder != nil && audioRecorder.isRecording)
      {
          self.pause()
      }
      else
      {
        if audioRecorder == nil {
            self.startRecorder()
        }else{
            self.resume()
        }
      }
      print("startRecording: self.isPaused = \(isPaused)")
      return getCurrent(call: call)
  }

  func isPause() -> Bool {
      if let audioRecorder = audioRecorder {
          return isPaused || !audioRecorder.isRecording
      }else{
          return isPaused
      }
  }

  private func pause() {
      if let audioRecorder = audioRecorder{
          if audioRecorder.isRecording{
              self.isPaused = true
              audioRecorder.pause()
              self.delegate?.onPause()
          }
      }
  }

  private func resume() {
      if let audioRecorder = audioRecorder {
          self.isPaused = false
          audioRecorder.record()
          self.delegate?.onResume()
      }
  }

  func getDocumentsDirectory(fileName: String) -> URL
  {
      let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
      return paths[0].appendingPathComponent(fileName)
  }

  func activatePermission(granted: @escaping (() -> Void)) {
      if let viewController = UIApplication.shared.visibleViewController {
          self.viewController = viewController
          switch AVAudioSession.sharedInstance().recordPermission {
              case .granted:
                  granted()
                  break
              case .denied:
                  self.navigateToAppSetting(viewController)
                  break
              case .undetermined:
                  AVAudioSession.sharedInstance().requestRecordPermission({ (permission) in
                      if permission {
                          granted()
                      }else{
                          self.navigateToAppSetting(viewController)
                      }
                  })
                  break
              default:
                  break
          }
      }
  }

  private func startRecorder()
  {
      do
      {
          try recordingSession.setCategory(.record, mode: .default, options: .mixWithOthers)
          try recordingSession.setActive(true)
          recordingSession.requestRecordPermission(){[unowned self] allowed in
              DispatchQueue.main.async {
                  print("allowed = \(allowed)")
                  if allowed {
                      do
                      {
                          let url = self.getDocumentsDirectory(fileName: fileName)
                          path = url.absoluteString
                          self.audioRecorder = try AVAudioRecorder(url: url, settings: self.settings)
                          self.audioRecorder.delegate = self
                          self.audioRecorder.isMeteringEnabled = true
                          self.audioRecorder.updateMeters()
                          self.audioRecorder.record()
                          self.meterTimer = Timer.scheduledTimer(timeInterval: 0.025, target:self, selector: #selector(self.updateAudioMeter(timer:)), userInfo:nil, repeats:true)
                      }catch let error {
                          print("error=\(error.localizedDescription)")
                          self.displayAlert(msg_title: "Error", msg_desc: error.localizedDescription, action_title: "OK")
                      }
                  } else {
                      // failed to record!
                      print("Don't have access to use your microphone.")
                      self.displayAlert(msg_title: "Error", msg_desc: "Don't have access to use your microphone.", action_title: "OK")
                  }
              }
          }
      }
      catch let error {
          self.displayAlert(msg_title: "Error", msg_desc: error.localizedDescription, action_title: "OK")
      }
  }

  private func finishRecording(call: FlutterMethodCall) -> [String : Any]?{
    let current = getCurrent(call: call)
    if let recorder = self.audioRecorder{
        recorder.stop()
        audioRecorder = nil
        meterTimer?.invalidate()

        do{
            try recordingSession.setActive(false)
        }catch let error{
            print("error = \(error.localizedDescription)")
        }
    }
    print("recorded successfully.")
    return current
  }

  private func displayAlert(msg_title : String , msg_desc : String ,action_title : String)
  {
      if let viewController = UIApplication.shared.visibleViewController {
          let ac = UIAlertController(title: msg_title, message: msg_desc, preferredStyle: .alert)
          ac.addAction(UIAlertAction(title: action_title, style: .default)
          {
              (result : UIAlertAction) -> Void in
              _ = viewController.navigationController?.popViewController(animated: true)
          })
          viewController.present(ac, animated: true)
      }

  }

  func navigateToAppSetting(_ viewController: UIViewController) {
      let title = "Mic Permission"
      let message = "\(Bundle.main.displayName) requires your mic permission"

      let alertController = UIAlertController (title: title, message: message, preferredStyle: .alert)

      let settingsAction = UIAlertAction(title: "Settings", style: .default) { (_) -> Void in
          guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
              return
          }

          if UIApplication.shared.canOpenURL(settingsUrl) {
              UIApplication.shared.open(settingsUrl, completionHandler: { (success) in
                  print("Settings opened: \(success)") // Prints true
              })
          }
      }
      alertController.addAction(settingsAction)
      let cancelAction = UIAlertAction(title: "Cancel", style: .default, handler: nil)
      alertController.addAction(cancelAction)

      viewController.present(alertController, animated: true, completion: nil)
  }

  @objc private func updateAudioMeter(timer: Timer)
  {
      if isPaused || audioRecorder == nil{
          return
      }
      if audioRecorder.isRecording
      {
          audioRecorder.updateMeters()
      }
  }

  func getAudios(call: FlutterMethodCall) -> [[String : Any]]?{
      let audios = UserDefaults.init(suiteName: "group.com.mcsd.MYC")
      let sharedAudios = audios?.value(forKey: "audios") as? [[String : Any]]
      if sharedAudios != nil {
          var arr: [[String : Any]] = [[:]]
          sharedAudios?.forEach({ (metaData) in
              let fileName = metaData["name"] as! String
              arr.append(["name":fileName])
              moveFileToMyApp(fileName)
          })
          audios?.removeObject(forKey: "audios")
          return arr
      }
      return nil
  }

  fileprivate func moveFileToMyApp(_ fileName: String) {
    let myAppURL = try! FileManager.default.url(for:.documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let fileURL = myAppURL.appendingPathComponent(fileName)
    //            let srcURL = URL(string: url)

    let realFileUrlString = appendSuffixName(fileURL: fileURL, seq: 0)
    let realFileUrl = URL(string: realFileUrlString)

    let documentsDirectory = FileManager().containerURL(forSecurityApplicationGroupIdentifier: "group.com.mcsd.MYC")

    let archiveURL = documentsDirectory?.appendingPathComponent(fileName)
    do {
        print("getGruopFile: archiveURL =\(String(describing: archiveURL?.absoluteString)) fileURL =\(realFileUrl!.absoluteString)")
        try FileManager.default.moveItem(at: archiveURL!, to: realFileUrl!)
        print("copy success")
    } catch (let error){
        print("share Cannot copy item at \(archiveURL!) to \(realFileUrl!): \(error)")
    }
  }

  fileprivate func appendSuffixName(fileURL: URL, seq: Int)->String {
      if FileManager().fileExists(atPath: fileURL.path) {
          let durl = try! FileManager.default.url(for:.documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

          let orgFileName = fileURL.lastPathComponent
          let orgFileNameWithoutEXT = orgFileName.replacingOccurrences(of: ".\(fileURL.pathExtension)", with: "")
          let tempseq = 1 + seq

          let lastIndex = orgFileNameWithoutEXT.lastIndex(of: "_")
          let endIndex = orgFileNameWithoutEXT.endIndex
          if(lastIndex != nil){

              if "_" != orgFileNameWithoutEXT.last {
                  let substringStratIndex = orgFileNameWithoutEXT.index(lastIndex!, offsetBy: 1)
                  let seqStr = orgFileNameWithoutEXT[substringStratIndex..<endIndex]
                  let oldseq = Int(seqStr)
                  if oldseq != nil {
                      let newseq = oldseq! + 1
                      let fileNameWithSEQ = "\(orgFileNameWithoutEXT[orgFileNameWithoutEXT.startIndex..<lastIndex!])_\(newseq).\(fileURL.pathExtension)"
                      let resultUrl = durl.appendingPathComponent(fileNameWithSEQ)

                      return appendSuffixName(fileURL: resultUrl, seq: newseq)
                  }else {
                      let fileNameWithSEQ = "\(orgFileNameWithoutEXT)_\(tempseq).\(fileURL.pathExtension)"
                      let resultUrl = durl.appendingPathComponent(fileNameWithSEQ)

                      return appendSuffixName(fileURL: resultUrl, seq: tempseq)
                  }
              }else {
                  let fileNameWithSEQ = "\(orgFileNameWithoutEXT)_\(tempseq).\(fileURL.pathExtension)"
                  let resultUrl = durl.appendingPathComponent(fileNameWithSEQ)

                  return appendSuffixName(fileURL: resultUrl, seq: tempseq)
              }
          }else {
              let fileNameWithSEQ = "\(orgFileNameWithoutEXT)_\(tempseq).\(fileURL.pathExtension)"
              let resultUrl = durl.appendingPathComponent(fileNameWithSEQ)

              return appendSuffixName(fileURL: resultUrl, seq: tempseq)
          }

      }
      return fileURL.absoluteString
  }
}

//record audio delegate
protocol RecordingDelegate {
    func onTimeInterval(timeIntervalCounter: String, dBLogValue : Float)

    func getLocation() -> String

    func getRecordName() -> String

    func onPause()

    func onResume()
}

extension UIApplication {
    var visibleViewController: UIViewController? {

        guard let rootViewController = keyWindow?.rootViewController else {
            return nil
        }

        return getVisibleViewController(rootViewController)
    }

    private func getVisibleViewController(_ rootViewController: UIViewController) -> UIViewController? {

        if let presentedViewController = rootViewController.presentedViewController {
            return getVisibleViewController(presentedViewController)
        }

        if let navigationController = rootViewController as? UINavigationController {
            return navigationController.visibleViewController
        }

        if let tabBarController = rootViewController as? UITabBarController {
            return tabBarController.selectedViewController
        }

        return rootViewController
    }
}

extension Bundle {
    // Name of the app - title under the icon.
    var displayName: String {
            return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                object(forInfoDictionaryKey: "CFBundleName") as! String
    }

    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

extension TimeInterval{
    func toSeconds() -> Int {
        let time = NSInteger(self)
        let seconds = time % 60
        return seconds
    }
}
