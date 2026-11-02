import SwiftUI

/// 04 Verify. Six cells and the design's own number pad.
struct VerifyCodeView: View {
    let email: String
    let mode: EntryMode

    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split
    @State private var digits: [Int] = []
    @State private var resendAt = Date.now.addingTimeInterval(30)

    var body: some View {
        StepScreen(
            stamp: "0.2 Verify",
            title: "Enter the code.",
            subtitle: "We sent six digits to \(email).",
            onBack: { model.route = .email(mode) },
            trailing: { resend },
            lead: {
                if split != .sideBySide {
                    CodeCells(digits: digits, cellHeight: split == .stacked ? 72 : 60)
                }
                if let error = model.error {
                    Text(error).textStyle(.small).foregroundStyle(Palette.ember)
                }
            },
            work: {
                if split == .sideBySide {
                    CodeCells(digits: digits, cellHeight: 68)
                }
                Spacer(minLength: 0)
                NumberPad(keyHeight: split == .single ? 48 : 60) { digit in
                    guard digits.count < 6 else { return }
                    digits.append(digit)
                    if digits.count == 6 { submit() }
                } onDelete: {
                    if !digits.isEmpty { digits.removeLast() }
                }
            },
            action: PrimaryAction(title: "Verify", busy: model.busy, enabled: digits.count == 6, action: submit)
        )
        .onAppear { model.error = nil }
    }

    private var resend: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Int(resendAt.timeIntervalSince(context.date).rounded(.up))
            if left > 0 {
                Stamp(String(format: "Resend in 0:%02d", left)).frame(minHeight: 44)
            } else {
                Button("Resend code") {
                    resendAt = .now.addingTimeInterval(30)
                    Task { await model.resendCode(to: email) }
                }
                .buttonStyle(.link)
            }
        }
    }

    private func submit() {
        guard digits.count == 6 else { return }
        let code = digits.map(String.init).joined()
        Task {
            await model.verify(email: email, code: code)
            if model.error != nil { digits = [] }
        }
    }
}
