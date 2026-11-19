import SwiftUI
import PlayLogic

private let rowWhite = Color.white
private let rowCurrent = Color(white: 0.9)
private let rowDark = Color(white: 0.25)
private let resumeColumnWidth: CGFloat = 110

/**
 * List of tracks: one row per track, two columns.
 *   left  - track name drawn on top of its progress bar
 *   right - stored Resume Point of the track ("null" when nothing is stored)
 * Clicking a row switches to that track (from its Resume Point, or from the start).
 */
struct TrackTable: View {
    @ObservedObject var logic: PlayLogicController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Track")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                Text("Resume Point")
                    .frame(width: resumeColumnWidth)
            }
            .font(.caption.bold())
            .padding(.vertical, 4)

            if logic.queue.isEmpty {
                Text("No tracks. Use \"Choose folder\" and pick a folder with mp3 files.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(logic.queue.enumerated()), id: \.element.id) { index, track in
                            TrackRow(logic: logic, track: track, isCurrent: index == logic.currentIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    logic.select(index: index)
                                }
                                .accessibilityIdentifier("track-row-\(track.key)")
                        }
                    }
                }
                .background(Color(white: 0.8))
            }
        }
    }
}

struct TrackRow: View {
    @ObservedObject var logic: PlayLogicController
    let track: PlayTrack
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 0) {
            if isCurrent {
                // Only the playing row redraws several times a second.
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    nameWithProgress(progress: logic.duration > 0 ? logic.position / logic.duration : 0)
                }
            } else {
                nameWithProgress(progress: 0)
            }

            Text(resumeText)
                .monospacedDigit()
                .foregroundStyle(rowDark)
                .frame(width: resumeColumnWidth)
                .frame(maxHeight: .infinity)
                .background(isCurrent ? rowCurrent : rowWhite)
                .accessibilityIdentifier("resume-point-\(track.key)")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var resumeText: String {
        if let point = logic.resumePoint(for: track.key) {
            return formatTime(point)
        }
        return "null"
    }

    /**
     * Name and progress bar in one: the label is drawn twice, normal and inverted
     * (white on dark gray), and the inverted copy is masked to the played part.
     * The edge cuts straight through the letters.
     */
    private func nameWithProgress(progress: Double) -> some View {
        ZStack(alignment: .leading) {
            nameLabel(text: rowDark, background: isCurrent ? rowCurrent : rowWhite)
            nameLabel(text: rowWhite, background: rowDark)
                .mask(alignment: .leading) {
                    GeometryReader { geometry in
                        Rectangle().frame(width: geometry.size.width * min(max(progress, 0), 1))
                    }
                }
        }
    }

    private func nameLabel(text: Color, background: Color) -> some View {
        Text(track.title)
            .lineLimit(1)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(background)
    }
}
