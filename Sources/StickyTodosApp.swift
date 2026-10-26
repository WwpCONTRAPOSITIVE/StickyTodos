import AppKit
import CoreGraphics
import SwiftUI

extension Notification.Name {
    static let createRepeatingTodo = Notification.Name("StickyTodos.createRepeatingTodo")
}

enum TodoCategory: String, CaseIterable, Codable, Identifiable {
    case finance, study, events, life, work

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finance: return "金融申请"
        case .study: return "学习"
        case .events: return "活动"
        case .life: return "生活"
        case .work: return "工作"
        }
    }

    var symbol: String {
        switch self {
        case .finance: return "building.columns"
        case .study: return "book"
        case .events: return "calendar"
        case .life: return "heart"
        case .work: return "briefcase"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "content" {
            self = .work
        } else if let category = TodoCategory(rawValue: value) {
            self = category
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "未知任务分类：\(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct TodoTask: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var category: TodoCategory
    var isDone: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date? = nil
    var scheduledFor: Date? = nil
    var boldSpans: [BoldSpan]? = nil
    var repeatRule: RepeatRule? = nil
    var completedOn: [Date]? = nil
}

enum RepeatRule: String, CaseIterable, Codable, Identifiable {
    case daily, weekly, monthly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
}

private struct StoredCategory: Decodable {
    let category: String
}

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var tasks: [TodoTask] = [] {
        didSet { save() }
    }
    @Published private(set) var saveError: String?

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("StickyTodos", isDirectory: true)
        fileURL = directory.appendingPathComponent("tasks.json")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode([TodoTask].self, from: data)
                let storedCategories = try JSONDecoder().decode(
                    [StoredCategory].self, from: data
                )
                let needsMigration = decoded.contains { $0.scheduledFor == nil }
                    || storedCategories.contains { $0.category == "content" }
                tasks = decoded.map { task in
                    var updated = task
                    if updated.scheduledFor == nil {
                        updated.scheduledFor = Calendar.current.startOfDay(for: Date())
                    }
                    return updated
                }
                if needsMigration { save() }
            } catch {
                saveError = "任务文件读取失败，原文件已保留。"
            }
        }
    }

    func add(
        _ rawTitle: String,
        to category: TodoCategory,
        on date: Date,
        repeatRule: RepeatRule? = nil
    ) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        tasks.append(TodoTask(
            title: title,
            category: category,
            scheduledFor: Calendar.current.startOfDay(for: date),
            repeatRule: repeatRule
        ))
    }

    func toggle(_ id: UUID, on date: Date) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if tasks[index].repeatRule != nil {
            var days = tasks[index].completedOn ?? []
            if let completedIndex = days.firstIndex(where: {
                Calendar.current.isDate($0, inSameDayAs: date)
            }) {
                days.remove(at: completedIndex)
            } else {
                days.append(Calendar.current.startOfDay(for: date))
            }
            tasks[index].completedOn = days
            return
        }
        tasks[index].isDone.toggle()
        tasks[index].completedAt = tasks[index].isDone ? Date() : nil
    }

    func rename(_ id: UUID, to rawTitle: String, boldSpans: [BoldSpan]) {
        guard !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var updated = tasks[index]
        updated.title = rawTitle
        updated.boldSpans = RichTextFormatting.normalizedSpans(
            boldSpans, in: rawTitle
        )
        tasks[index] = updated
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
    }

    func reschedule(_ id: UUID, to date: Date) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].scheduledFor = Calendar.current.startOfDay(for: date)
    }

    func isDone(_ task: TodoTask, on date: Date) -> Bool {
        guard task.repeatRule != nil else { return task.isDone }
        return (task.completedOn ?? []).contains {
            Calendar.current.isDate($0, inSameDayAs: date)
        }
    }

    func isScheduled(_ task: TodoTask, on date: Date) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: task.scheduledFor ?? task.createdAt)
        let day = calendar.startOfDay(for: date)
        guard day >= start else { return false }
        guard let rule = task.repeatRule else {
            return calendar.isDate(start, inSameDayAs: day)
        }

        switch rule {
        case .daily:
            return true
        case .weekly:
            let gap = calendar.dateComponents([.day], from: start, to: day).day ?? -1
            return gap >= 0 && gap % 7 == 0
        case .monthly, .yearly:
            let first = calendar.dateComponents([.era, .year, .month, .day], from: start)
            let current = calendar.dateComponents([.era, .year, .month, .day], from: day)
            guard first.era == current.era,
                  let firstYear = first.year, let currentYear = current.year,
                  let firstMonth = first.month, let currentMonth = current.month,
                  let firstDay = first.day, let currentDay = current.day,
                  let lastDay = calendar.range(of: .day, in: .month, for: day)?.count
            else { return false }
            if rule == .monthly {
                let months = (currentYear - firstYear) * 12 + currentMonth - firstMonth
                return months >= 0 && currentDay == min(firstDay, lastDay)
            }
            return currentYear >= firstYear
                && currentMonth == firstMonth
                && currentDay == min(firstDay, lastDay)
        }
    }

    private func save() {
        // A failed read must never be replaced with an empty task list.
        guard saveError == nil else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            saveError = "保存失败：\(error.localizedDescription)"
        }
    }
}

private enum WindowMode: String, CaseIterable, Identifiable {
    case desktop, floating, normal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "桌面小组件"
        case .floating: return "始终置顶"
        case .normal: return "普通窗口"
        }
    }

    var symbol: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .floating: return "pin.fill"
        case .normal: return "macwindow"
        }
    }
}

private final class DesktopWindowView: NSView {
    var mode: WindowMode = .desktop {
        didSet {
            guard oldValue != mode else { return }
            configureWindow()
            if mode != .desktop {
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    private func configureWindow() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        switch mode {
        case .desktop:
            // Above Finder's desktop icons, but behind ordinary app windows.
            let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
            window.level = NSWindow.Level(rawValue: desktopLevel)
            window.collectionBehavior = [
                .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone
            ]
        case .floating:
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        case .normal:
            window.level = .normal
            window.collectionBehavior = []
        }
        window.setFrameAutosaveName("StickyTodosWindow")
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let mode: WindowMode

    func makeNSView(context: Context) -> DesktopWindowView {
        let view = DesktopWindowView()
        view.mode = mode
        return view
    }

    func updateNSView(_ view: DesktopWindowView, context: Context) {
        view.mode = mode
    }
}

private enum TaskTab: String, CaseIterable, Identifiable {
    case todo = "待办"
    case done = "已完成"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @AppStorage("StickyTodos.windowMode") private var windowMode = WindowMode.desktop.rawValue
    @FocusState private var addFieldFocused: Bool
    @State private var tab: TaskTab = .todo
    @State private var category: TodoCategory = .work
    @State private var newTitle = ""
    @State private var collapsed: Set<TodoCategory> = []
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var showingCalendar = false
    @State private var showingRepeatCreator = false

    private var visibleTasks: [TodoTask] {
        store.tasks.filter { task in
            store.isScheduled(task, on: selectedDate)
                && store.isDone(task, on: selectedDate) == (tab == .done)
        }
    }

    private var selectedWindowMode: WindowMode {
        WindowMode(rawValue: windowMode) ?? .desktop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            dateNavigation
                .padding(.top, 14)
            tabs
                .padding(.top, 14)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if visibleTasks.isEmpty {
                        emptyState
                    }
                    ForEach(TodoCategory.allCases) { group in
                        let items = visibleTasks.filter { $0.category == group }
                        if tab == .todo || !items.isEmpty {
                            categorySection(group, items: items)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = store.saveError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }

            addBar
                .padding(.top, 14)
        }
        .padding(22)
        .frame(minWidth: 330, idealWidth: 370, minHeight: 420, idealHeight: 520)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.78))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.38), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.17), radius: 24, y: 12)
        .background(WindowAccessor(mode: selectedWindowMode))
        .onReceive(NotificationCenter.default.publisher(for: .createRepeatingTodo)) { _ in
            showingRepeatCreator = true
        }
        .sheet(isPresented: $showingRepeatCreator) {
            RepeatTaskForm(startDate: selectedDate) { title, selectedCategory, date, rule in
                store.add(title, to: selectedCategory, on: date, repeatRule: rule)
                selectedDate = date
                tab = .todo
                collapsed.remove(selectedCategory)
                showingRepeatCreator = false
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TODO / 待办")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(WindowMode.allCases) { mode in
                    Button {
                        windowMode = mode.rawValue
                    } label: {
                        Label(
                            mode.title,
                            systemImage: mode == selectedWindowMode
                                ? "checkmark.circle.fill" : mode.symbol
                        )
                    }
                }
            } label: {
                Image(systemName: selectedWindowMode.symbol)
                    .font(.system(size: 12))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .help("显示位置：\(selectedWindowMode.title)")

            Menu {
                Button("新建重复待办…") { showingRepeatCreator = true }
                Divider()
                Button("退出应用") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
        }
    }

    private var dateNavigation: some View {
        HStack(spacing: 8) {
            Button {
                moveDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 20, height: 26)
            }
            .buttonStyle(.plain)
            .help("前一天")

            Button {
                showingCalendar = true
            } label: {
                HStack(spacing: 6) {
                    Text(selectedDate.formatted(.dateTime.year().month().day().weekday(.abbreviated)))
                        .lineLimit(1)
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                }
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("从日历选择日期")
            .popover(isPresented: $showingCalendar) {
                DatePicker("选择日期", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
                    .frame(width: 290)
            }

            Button {
                moveDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 20, height: 26)
            }
            .buttonStyle(.plain)
            .help("后一天")

            Spacer(minLength: 0)

            if !Calendar.current.isDateInToday(selectedDate) {
                Button("今天") {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func moveDate(by days: Int) {
        selectedDate = Calendar.current.date(
            byAdding: .day,
            value: days,
            to: selectedDate
        ) ?? selectedDate
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(TaskTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 11, weight: tab == item ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(tab == item ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if tab == item {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.53))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

    private var emptyState: some View {
        Text(tab == .todo ? "这一天还没有待办。" : "这一天还没有已完成的任务。")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func categorySection(_ group: TodoCategory, items: [TodoTask]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                if collapsed.contains(group) {
                    collapsed.remove(group)
                } else {
                    collapsed.insert(group)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsed.contains(group) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed.contains(group) {
                ForEach(items) { task in
                    TaskRow(task: task, viewedDate: selectedDate)
                        .environmentObject(store)
                }
            }
        }
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(TodoCategory.allCases) { group in
                    Button {
                        category = group
                    } label: {
                        Label(group.title, systemImage: group.symbol)
                    }
                }
            } label: {
                Image(systemName: category.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("分类：\(category.title)")

            TextField("添加新任务…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($addFieldFocused)
                .onSubmit(addTask)

            Button(action: addTask) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("添加任务")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 10))
    }

    private func addTask() {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.add(newTitle, to: category, on: selectedDate)
        newTitle = ""
        tab = .todo
        collapsed.remove(category)
        addFieldFocused = true
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var store: TodoStore
    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var editedSpans: [BoldSpan] = []
    @State private var editorHandle = RichTextEditorHandle()
    @State private var showingDatePicker = false
    @State private var dateDraft = Date()

    let task: TodoTask
    let viewedDate: Date

    private var completed: Bool {
        store.isDone(task, on: viewedDate)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                store.toggle(task.id, on: viewedDate)
            } label: {
                Image(systemName: completed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(completed ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .help(completed ? "标记为待办" : "标记为完成")

            RichTextFormatting.displayText(task.title, spans: task.boldSpans ?? [])
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(completed ? .secondary : .primary)
                .strikethrough(completed)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: startEdit)

            if let rule = task.repeatRule {
                Image(systemName: "repeat")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help(rule.title + "重复")
            }
        }
        .padding(.leading, 3)
        .padding(.vertical, 2)
        .contextMenu {
            Button("编辑任务文字…") { startEdit() }
            Button("修改日期…") {
                dateDraft = task.scheduledFor ?? task.createdAt
                showingDatePicker = true
            }
            Button(
                task.repeatRule == nil ? "删除" : "删除整个重复任务",
                role: .destructive
            ) { store.delete(task.id) }
        }
        .sheet(isPresented: $isEditing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("编辑任务")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Text("选中文字后点击 B，或按 ⌘B 加粗／取消加粗")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                RichTextEditor(
                    text: $editedTitle,
                    spans: $editedSpans,
                    handle: editorHandle
                )
                .frame(height: 120)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                HStack {
                    Button {
                        editorHandle.toggleBold()
                    } label: {
                        Text("B").bold().frame(width: 26)
                    }
                    .help("加粗选中文字（⌘B）")
                    Spacer()
                    Button("取消") { isEditing = false }
                    Button("保存") { commitEdit() }
                        .disabled(editedTitle.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty)
                }
            }
            .padding(18)
            .frame(width: 350)
        }
        .popover(isPresented: $showingDatePicker) {
            VStack(alignment: .leading, spacing: 12) {
                Text("修改任务日期")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                DatePicker("日期", selection: $dateDraft, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Spacer()
                    Button("取消") { showingDatePicker = false }
                    Button("保存") {
                        store.reschedule(task.id, to: dateDraft)
                        showingDatePicker = false
                    }
                }
            }
            .padding(14)
            .frame(width: 290)
        }
    }

    private func startEdit() {
        editedTitle = task.title
        editedSpans = task.boldSpans ?? []
        isEditing = true
    }

    private func commitEdit() {
        store.rename(task.id, to: editedTitle, boldSpans: editedSpans)
        isEditing = false
    }
}

@main
struct StickyTodosApp: App {
    @StateObject private var store = TodoStore()

    var body: some Scene {
        WindowGroup("Todo 便签") {
            ContentView()
                .environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 370, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("任务") {
                Button("新建重复待办…") {
                    NotificationCenter.default.post(
                        name: .createRepeatingTodo, object: nil
                    )
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
