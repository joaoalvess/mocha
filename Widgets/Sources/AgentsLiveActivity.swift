import ActivityKit
import MochaProtocol
import SwiftUI
import WidgetKit

struct AgentsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MochaAgentsAttributes.self) { context in
            Text("\(context.state.working) trabalhando · \(context.state.waiting) esperando você")
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.working) trabalhando · \(context.state.waiting) esperando você")
                }
            } compactLeading: {
                Image(systemName: "asterisk")
            } compactTrailing: {
                Text("\(context.state.working)")
            } minimal: {
                Image(systemName: "asterisk")
            }
        }
    }
}
