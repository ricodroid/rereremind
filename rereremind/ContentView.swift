//
//  ContentView.swift
//  rereremind
//
//  Created by riko on 2025/02/24.
//
import SwiftUI
import UserNotifications

struct ContentView: View {
    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var lastUserInput: String = ""
    @State private var reminders: [Reminder] = []
    @State private var showReminderList = false
    @State private var showSnoozeView = false
    @State private var snoozeReminder: Reminder?

    @ObservedObject var notificationHandler = NotificationHandler.shared // 🔹 `NotificationHandler` を監視

    let remindersKey = "savedReminders"

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            HStack {
                                if message.isUser {
                                    Spacer()
                                    Text(message.text)
                                        .padding()
                                        .background(Color.blue.opacity(0.7))
                                        .cornerRadius(10)
                                        .foregroundColor(.white)
                                } else {
                                    Text(message.text)
                                        .padding()
                                        .background(Color.gray.opacity(0.3))
                                        .cornerRadius(10)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding()

                HStack {
                    TextField("メッセージを入力", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("送信") {
                        sendMessage()
                    }
                }
                .padding()

                Button("リマインダー一覧を表示") {
                    showReminderList = true
                }
                .padding()
            }
            .navigationTitle("リマインダーBot")
            .onAppear {
                loadReminders()
                
                // 0.5秒後に実行して、リマインダーの削除を遅延
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    filterValidReminders()
                }

                NotificationHandler.shared.requestAuthorization() // 🔹 通知許可をリクエスト
            }
            // 🔹 `showSnoozeView` の変更を監視
            .onChange(of: notificationHandler.showSnoozeView) { _, _ in
                            if notificationHandler.showSnoozeView, let reminder = notificationHandler.snoozeReminder {
                                print("🟢 SnoozeView を表示します")
                                self.snoozeReminder = reminder
                                self.showSnoozeView = true
                                notificationHandler.showSnoozeView = false // 🔹 一度開いたらリセット
                            }
            }
            .sheet(isPresented: $showReminderList) {
                ReminderListView(reminders: $reminders, updateReminder: updateReminder) // 🔹 `updateReminder` を渡す
            }
            .sheet(isPresented: $showSnoozeView) {
                if let reminder = snoozeReminder {
                    SnoozeView(reminder: reminder, updateReminder: updateReminder) // 🔹 `updateReminder` を渡す
                }
            }
        }
    }

    func updateReminder(oldReminder: Reminder, newDate: Date) {
        if let index = reminders.firstIndex(where: { $0.id == oldReminder.id }) {
            let updatedReminder = Reminder(id: oldReminder.id, text: oldReminder.text, date: newDate)
            
            // 🔹 まず古い通知を削除
            cancelNotification(for: oldReminder)

            // 🔹 リマインダーリストを更新
            reminders[index] = updatedReminder
            saveReminders()

            // 🔹 新しい通知をスケジュール
            scheduleNotification(at: newDate, message: oldReminder.text)

            // 🔹 1秒後に filterValidReminders() を実行
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.filterValidReminders()
            }
        }
    }


    func saveReminders() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(reminders) {
            UserDefaults.standard.set(encoded, forKey: remindersKey)
        }
    }

    func cancelNotification(for reminder: Reminder) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let matchingRequests = requests.filter { $0.content.body == reminder.text }
            
            // 🔹 IDが一致する通知を削除
            let identifiersToRemove = matchingRequests.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
            
            if !identifiersToRemove.isEmpty {
                print("📌 通知削除: \(identifiersToRemove)")
            }
        }
    }


    func sendMessage() {
            let userMessage = Message(text: inputText, isUser: true)
            messages.append(userMessage)
            
            if lastUserInput.isEmpty {
                lastUserInput = inputText
                let botPromptMessage = Message(text: "\"\(inputText)\" ですね！ いつ教えて欲しいですか？", isUser: false)
                messages.append(botPromptMessage)
            } else if let date = extractDateTime(from: inputText) {
                let now = Date()
                if date < now {
                    let botPastDateMessage = Message(text: "未来の日付で答えてください！いつ教えて欲しいですか？", isUser: false)
                    messages.append(botPastDateMessage)
                } else {
                    let reminder = Reminder(text: lastUserInput, date: date)
                    reminders.append(reminder) // リストに追加
                    saveReminders() // 永続化
                    
                    let botConfirmationMessage = Message(text: "\(formatDate(date)) にリマインドしますね！", isUser: false)
                    messages.append(botConfirmationMessage)
                    scheduleNotification(at: date, message: lastUserInput)
                    lastUserInput = ""
                }
            } else {
                let botErrorMessage = Message(text: "すみません、わかりませんでした。正しい日付で教えてください。", isUser: false)
                messages.append(botErrorMessage)
            }
            
            inputText = ""
        }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
    
    func extractDateTime(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)

        // Date patterns (Japanese & English)
        let datePatterns = [
            "\\d{4}/\\d{1,2}/\\d{1,2}",         // 2025/5/1, 2026/1/1
            "\\d{1,2}/\\d{1,2}",                // 5/1
            "\\d{1,2}月\\d{1,2}日",            // 5月1日
            "\\d{4}年\\d{1,2}月\\d{1,2}日",    // 2025年5月1日
            "今日|きょう|today",
            "明日|あした|tomorrow",
            "明後日|あさって|day after tomorrow",
            "明々後日|three days later"
        ]

        for pattern in datePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let matchedDate = String(text[match])
                if ["今日", "きょう", "today"].contains(matchedDate) {
                    // Today (no changes needed)
                } else if ["明日", "あした", "tomorrow"].contains(matchedDate) {
                    components.day! += 1
                } else if ["明後日", "あさって", "day after tomorrow"].contains(matchedDate) {
                    components.day! += 2
                } else if ["明々後日", "three days later"].contains(matchedDate) {
                    components.day! += 3
                } else {
                    let dateFormats = ["yyyy/M/d", "yyyy年M月d日", "M/d", "MM/dd", "MMMM d", "MMMM d, yyyy"]
                    for format in dateFormats {
                        formatter.dateFormat = format
                        if let parsedDate = formatter.date(from: matchedDate) {
                            components.year = calendar.component(.year, from: parsedDate)
                            components.month = calendar.component(.month, from: parsedDate)
                            components.day = calendar.component(.day, from: parsedDate)
                            break
                        }
                    }
                }
                break
            }
        }

        // Time patterns (Japanese & English)
        let timePatterns = [
            "\\d{1,2}:\\d{2}",          // 9:00, 21:30
            "\\d{1,2}時",               // 9時, 21時
            "\\d{1,2}：\\d{2}",         // ９：００
            "\\d{1,2}:\\d{2} (am|pm)"   // 9:00 am, 10:30 pm
        ]

        var foundTime = false
        for pattern in timePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                var matchedTime = String(text[match]).replacingOccurrences(of: "：", with: ":")
                if matchedTime.contains("時") {
                    matchedTime = matchedTime.replacingOccurrences(of: "時", with: ":00")
                }
                formatter.dateFormat = "h:mm a" // Handles both "9:00" and "9:00 am/pm"
                if let parsedTime = formatter.date(from: matchedTime) {
                    components.hour = calendar.component(.hour, from: parsedTime)
                    components.minute = calendar.component(.minute, from: parsedTime)
                    foundTime = true
                    break
                }
            }
        }

        if !foundTime {
            components.hour = 9
            components.minute = 0
        }

        let extractedDate = calendar.date(from: components)

        // Avoid past dates
        if let date = extractedDate, date < now {
            return nil
        }

        return extractedDate
    }
    
    func loadReminders() {
            if let savedData = UserDefaults.standard.data(forKey: remindersKey) {
                let decoder = JSONDecoder()
                if let loadedReminders = try? decoder.decode([Reminder].self, from: savedData) {
                    reminders = loadedReminders
                }
            }
        }
    
    func filterValidReminders() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                let requestBodies = requests.map { $0.content.body }
                
                // 🔹 "削除" ではなく、有効な通知をリストに残す
                self.reminders = self.reminders.filter { reminder in
                    requestBodies.contains(reminder.text)
                }

                self.saveReminders() // 更新後に再保存
            }
        }
    }


    
    func scheduleNotification(at date: Date, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "リマインダー"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "REMINDER_CATEGORY" // 🔹 通知カテゴリーを設定

        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("通知のスケジュールに失敗: \(error.localizedDescription)")
            }
        }
    }

}

#Preview {
    ContentView()
}
