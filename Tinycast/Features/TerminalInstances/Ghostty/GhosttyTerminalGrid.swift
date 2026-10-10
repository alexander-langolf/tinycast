import Foundation
import GhosttyVt
import Observation

/// FORK: libghostty prototype. A ghostty terminal plus its render state, read out as plain rows.
///
/// Main actor only: ghostty callbacks run synchronously inside `feed`, on the caller's thread.
@MainActor
@Observable
final class GhosttyTerminalGrid {
    struct Cell: Equatable {
        var text: String
        /// 0xRRGGBB; nil is the default colour.
        var foreground: UInt32?
        var background: UInt32?
        var bold = false
        var italic = false
        var faint = false
        var inverse = false
        var underline = false
        var strikethrough = false
    }

    struct Snapshot {
        var rows: [[Cell]] = []
        var cursor: (x: Int, y: Int)?
        var cursorVisible = false
        /// Rows from the top down to the last one holding text or the cursor.
        var contentRows = 0
    }

    private(set) var columns: Int
    private(set) var rows: Int
    /// Bumps on every change, so a view that reads it redraws.
    private(set) var revision = 0
    private(set) var snapshot = Snapshot()
    private(set) var isAlternateScreen = false
    private(set) var scrollbar = GhosttyTerminalScrollbar()

    /// Bytes the terminal wants written back to the pty: query replies and the like.
    @ObservationIgnored var writeToPty: (([UInt8]) -> Void)?

    @ObservationIgnored private var terminal: GhosttyTerminal?
    @ObservationIgnored private var renderState: GhosttyRenderState?
    @ObservationIgnored private var rowIterator: GhosttyRenderStateRowIterator?
    @ObservationIgnored private var rowCells: GhosttyRenderStateRowCells?
    @ObservationIgnored private var keyEncoder: GhosttyKeyEncoder?
    @ObservationIgnored private var keyEvent: GhosttyKeyEvent?

    private static let scrollbackLines = 10_000

    init?(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        guard
            ghostty_terminal_new(nil, &terminal, UInt16(clamping: columns), UInt16(clamping: rows))
                == GHOSTTY_SUCCESS,
            let terminal,
            ghostty_render_state_new(nil, &renderState) == GHOSTTY_SUCCESS,
            ghostty_render_state_row_iterator_new(nil, &rowIterator) == GHOSTTY_SUCCESS,
            ghostty_render_state_row_cells_new(nil, &rowCells) == GHOSTTY_SUCCESS,
            ghostty_key_encoder_new(nil, &keyEncoder) == GHOSTTY_SUCCESS,
            ghostty_key_event_new(nil, &keyEvent) == GHOSTTY_SUCCESS
        else { return nil }
        var limit = Self.scrollbackLines
        _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES, &limit)
        _ = ghostty_terminal_set(
            terminal, GHOSTTY_TERMINAL_OPT_USERDATA, Unmanaged.passUnretained(self).toOpaque())
        let writePty: GhosttyTerminalWritePtyFn = { _, userdata, data, length in
            guard let userdata, let data else { return }
            let bytes = Array(UnsafeBufferPointer(start: data, count: length))
            let grid = Unmanaged<GhosttyTerminalGrid>.fromOpaque(userdata)
            MainActor.assumeIsolated { grid.takeUnretainedValue().writeToPty?(bytes) }
        }
        _ = ghostty_terminal_set(
            terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(writePty, to: UnsafeRawPointer.self))
        refresh()
    }

    isolated deinit {
        ghostty_key_event_free(keyEvent)
        ghostty_key_encoder_free(keyEncoder)
        ghostty_render_state_row_cells_free(rowCells)
        ghostty_render_state_row_iterator_free(rowIterator)
        ghostty_render_state_free(renderState)
        ghostty_terminal_free(terminal)
    }

    func feed(_ bytes: [UInt8]) {
        guard let terminal, !bytes.isEmpty else { return }
        bytes.withUnsafeBufferPointer { ghostty_terminal_vt_write(terminal, $0.baseAddress, $0.count) }
        refresh()
    }

    /// RIS: a new command starts on a clean screen with no scrollback.
    func reset() {
        ghostty_terminal_reset(terminal)
        refresh()
    }

    func resize(columns: Int, rows: Int) {
        guard let terminal, columns > 0, rows > 0, (columns, rows) != (self.columns, self.rows) else {
            return
        }
        self.columns = columns
        self.rows = rows
        _ = ghostty_terminal_resize(terminal, UInt16(clamping: columns), UInt16(clamping: rows), 0, 0)
        refresh()
    }

    /// Negative scrolls up into the scrollback.
    func scroll(by delta: Int) {
        guard let terminal, delta != 0 else { return }
        ghostty_terminal_scroll_viewport(
            terminal,
            GhosttyTerminalScrollViewport(
                tag: GHOSTTY_SCROLL_VIEWPORT_DELTA, value: GhosttyTerminalScrollViewportValue(delta: delta)))
        refresh()
    }

    func scrollToBottom() {
        guard let terminal else { return }
        ghostty_terminal_scroll_viewport(
            terminal,
            GhosttyTerminalScrollViewport(
                tag: GHOSTTY_SCROLL_VIEWPORT_BOTTOM, value: GhosttyTerminalScrollViewportValue(delta: 0)))
        refresh()
    }

    /// A special key through ghostty's own encoder, so cursor-key and kitty-protocol modes are honoured.
    func encode(key: GhosttyKey, mods: GhosttyMods) -> [UInt8] {
        guard let terminal, let keyEncoder, let keyEvent else { return [] }
        ghostty_key_encoder_setopt_from_terminal(keyEncoder, terminal)
        ghostty_key_event_set_action(keyEvent, GHOSTTY_KEY_ACTION_PRESS)
        ghostty_key_event_set_key(keyEvent, key)
        ghostty_key_event_set_mods(keyEvent, mods)
        ghostty_key_event_set_utf8(keyEvent, nil, 0)
        var buffer = [CChar](repeating: 0, count: 64)
        var written = 0
        guard
            ghostty_key_encoder_encode(keyEncoder, keyEvent, &buffer, buffer.count, &written)
                == GHOSTTY_SUCCESS
        else { return [] }
        return buffer[0..<written].map { UInt8(bitPattern: $0) }
    }

    // MARK: - Read-out

    private func refresh() {
        guard let terminal, let renderState else { return }
        var screen = GHOSTTY_TERMINAL_SCREEN_PRIMARY
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &screen)
        isAlternateScreen = screen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE
        var bar = GhosttyTerminalScrollbar()
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SCROLLBAR, &bar)
        scrollbar = bar

        guard ghostty_render_state_update(renderState, terminal) == GHOSTTY_SUCCESS else { return }
        var next = Snapshot()
        var cursor = GhosttyRenderStateCursor()
        cursor.size = MemoryLayout<GhosttyRenderStateCursor>.size
        if ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR, &cursor) == GHOSTTY_SUCCESS
        {
            next.cursorVisible = cursor.visible
            if cursor.viewport_has_value { next.cursor = (Int(cursor.viewport_x), Int(cursor.viewport_y)) }
        }
        if let rowIterator, let rowCells {
            var iterator: GhosttyRenderStateRowIterator? = rowIterator
            _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator)
            var y = 0
            while ghostty_render_state_row_iterator_next(rowIterator) {
                var cellsHandle: GhosttyRenderStateRowCells? = rowCells
                _ = ghostty_render_state_row_get(
                    rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cellsHandle)
                var row: [Cell] = []
                row.reserveCapacity(columns)
                while ghostty_render_state_row_cells_next(rowCells) {
                    row.append(readCell(rowCells))
                }
                if row.contains(where: { !$0.text.isEmpty }) { next.contentRows = y + 1 }
                next.rows.append(row)
                y += 1
            }
        }
        if let position = next.cursor { next.contentRows = max(next.contentRows, position.y + 1) }
        snapshot = next
        revision &+= 1
    }

    private func readCell(_ cells: GhosttyRenderStateRowCells) -> Cell {
        var length: UInt32 = 0
        _ = ghostty_render_state_row_cells_get(
            cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &length)
        var cell = Cell(text: "")
        if length > 0 {
            var scalars = [UInt32](repeating: 0, count: Int(length))
            _ = ghostty_render_state_row_cells_get(
                cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, &scalars)
            var text = String.UnicodeScalarView()
            for value in scalars { if let scalar = Unicode.Scalar(value) { text.append(scalar) } }
            cell.text = String(text)
        }
        var hasStyling = false
        _ = ghostty_render_state_row_cells_get(
            cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING, &hasStyling)
        if hasStyling {
            var style = GhosttyStyle()
            style.size = MemoryLayout<GhosttyStyle>.size
            _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style)
            cell.bold = style.bold
            cell.italic = style.italic
            cell.faint = style.faint
            cell.inverse = style.inverse
            cell.underline = style.underline != 0
            cell.strikethrough = style.strikethrough
            var rgb = GhosttyColorRgb()
            if ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &rgb)
                == GHOSTTY_SUCCESS
            {
                cell.foreground = UInt32(rgb.r) << 16 | UInt32(rgb.g) << 8 | UInt32(rgb.b)
            }
        }
        // Background-only cells carry no style, so this is read for every cell.
        var background = GhosttyColorRgb()
        if ghostty_render_state_row_cells_get(
            cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &background)
            == GHOSTTY_SUCCESS
        {
            cell.background = UInt32(background.r) << 16 | UInt32(background.g) << 8 | UInt32(background.b)
        }
        return cell
    }
}
