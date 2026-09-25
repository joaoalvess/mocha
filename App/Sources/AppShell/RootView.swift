import SwiftUI

struct RootView: View {
    var body: some View {
        #if DEBUG
        switch DebugProbe.fromLaunchArguments() {
        case .push:
            PushProbeView()
        case .gateway:
            GatewayProbeView()
        case nil:
            SplashView()
        }
        #else
        SplashView()
        #endif
    }
}

#if DEBUG
enum DebugProbe: String {
    case push
    case gateway

    static func fromLaunchArguments() -> DebugProbe? {
        UserDefaults.standard.string(forKey: "probe").flatMap(DebugProbe.init(rawValue:))
    }
}
#endif
