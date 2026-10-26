import SwiftUI

struct RepeatTaskForm: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var title = ""
    @State private var category: TodoCategory = .work
    @State private var date: Date
    @State private var rule: RepeatRule = .daily

    let onCreate: (String, TodoCategory, Date, RepeatRule) -> Void

    init(
        startDate: Date,
        onCreate: @escaping (String, TodoCategory, Date, RepeatRule) -> Void
    ) {
        _date = State(initialValue: startDate)
        self.onCreate = onCreate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建重复待办")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))

            TextField("要重复做什么？", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit(create)

            Picker("分类", selection: $category) {
                ForEach(TodoCategory.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            DatePicker("开始日期", selection: $date, displayedComponents: .date)

            Picker("重复周期", selection: $rule) {
                ForEach(RepeatRule.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            Text("每次出现都可以单独勾选完成。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建") { create() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { titleFocused = true }
    }

    private func create() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        onCreate(title, category, date, rule)
        dismiss()
    }
}
