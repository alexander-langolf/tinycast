import SwiftUI

/// The join preview: your camera over the meeting it is about to open.
struct CameraPreviewView: View {
    @Environment(CalendarCoordinator.self) private var coordinator
    let meeting: MeetingEvent
    let now: Date
    let feed: CameraSession.Feed
    let onJoin: () -> Void
    let onCancel: () -> Void

    private var metrics: InterfaceMetrics { coordinator.cameraMetrics }

    var body: some View {
        VStack(spacing: 0) {
            CameraStage(feed: feed)
                .frame(
                    width: Theme.Size.cameraPreview.width,
                    height: Theme.Size.cameraPreview.height)
            footer
        }
        .frame(width: Theme.Size.cameraPreview.width)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .panelEntrance()
        .environment(\.metrics, metrics)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(meeting.title)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                Text(UpcomingWindow.countdown(to: meeting.start, now: now))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.md)
            CameraButton(title: "Cancel", keyCap: "esc", emphasis: .secondary, onActivate: onCancel)
            CameraButton(title: "Join", keyCap: "↵", onActivate: onJoin)
        }
        .padding(Theme.Spacing.xl)
    }
}
