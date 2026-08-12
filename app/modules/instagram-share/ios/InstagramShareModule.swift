import ExpoModulesCore
import UIKit

// 인스타그램 스토리 1탭 공유 — 네이티브가 반드시 필요한 이유 하나 때문에 존재하는 모듈.
//
// `instagram-stories://share`를 그냥 열면 **이미지가 실리지 않는다.** 인스타는 이미지를 URL이 아니라
// iOS 페이스트보드의 **키 있는 딕셔너리**(com.instagram.sharedSticker.backgroundImage)로 받는다.
// React Native의 Share.share는 그 딕셔너리를 만들 수 없다 — setItems(_:options:)는 네이티브 API다.
// 그래서 이 파일이 있다. 하는 일은 딱 두 가지: 설치 여부를 정직하게 답하고, 이미지를 넘긴다.
//
// ⚠ canOpenURL은 Info.plist의 LSApplicationQueriesSchemes에 `instagram-stories`가 없으면
//   **항상 false**를 돌려준다 (실패가 아니라 침묵). app.json과 ios/app/Info.plist 양쪽에 있다.
public class InstagramShareModule: Module {
  private static let scheme = "instagram-stories://share"

  public func definition() -> ModuleDefinition {
    Name("InstagramShare")

    // 설치 여부. 이걸로 UI가 버튼을 그릴지 결정한다 — 없는 앱으로 가는 버튼은 죽은 버튼이다.
    // ⚠ 동기 Function에는 `.runOnQueue`가 없다 (AsyncFunction에만 있다 — 빌드가 그렇게 가르쳐줬다).
    //   canOpenURL은 UIKit이라 메인 스레드를 요구하므로 직접 건넌다. isMainThread 검사가 필수다:
    //   이미 메인인데 sync로 다시 들어가면 교착한다.
    Function("isAvailable") { () -> Bool in
      guard let url = URL(string: InstagramShareModule.scheme) else { return false }
      if Thread.isMainThread {
        return UIApplication.shared.canOpenURL(url)
      }
      var ok = false
      DispatchQueue.main.sync { ok = UIApplication.shared.canOpenURL(url) }
      return ok
    }

    // base64 PNG를 스토리 배경으로 넘기고 인스타를 연다.
    // 성공/실패를 삼키지 않는다: 설치 안 됨·이미지 손상·열기 실패가 각각 다른 문장으로 올라간다.
    AsyncFunction("shareToStories") { (base64: String, appId: String, promise: Promise) in
      guard let data = Data(base64Encoded: base64) else {
        promise.reject("E_BAD_IMAGE", "이미지를 읽지 못했어요")
        return
      }
      guard let url = URL(string: "\(InstagramShareModule.scheme)?source_application=\(appId)") else {
        promise.reject("E_BAD_URL", "인스타그램 주소를 만들지 못했어요")
        return
      }
      guard UIApplication.shared.canOpenURL(url) else {
        promise.reject("E_NOT_INSTALLED", "인스타그램이 설치돼 있지 않아요")
        return
      }
      // 만료 5분 — 페이스트보드에 사용자의 러닝 이미지를 무기한 남겨두지 않는다.
      // 인스타가 즉시 읽어가므로 5분은 넉넉하고, 그 뒤엔 iOS가 알아서 지운다.
      let items: [[String: Any]] = [["com.instagram.sharedSticker.backgroundImage": data]]
      UIPasteboard.general.setItems(
        items,
        options: [UIPasteboard.OptionsKey.expirationDate: Date().addingTimeInterval(300)]
      )
      UIApplication.shared.open(url, options: [:]) { opened in
        if opened { promise.resolve(true) }
        else { promise.reject("E_OPEN_FAILED", "인스타그램을 열지 못했어요") }
      }
    }.runOnQueue(.main)
  }
}
