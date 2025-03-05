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
                ZStack {
                    // 背景のグラデーション
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.2),
                            Color.blue.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .edgesIgnoringSafeArea(.all)

                    VStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(messages) { message in
                                    HStack {
                                        if message.isUser {
                                            Spacer()
                                            Text(message.text)
                                                .padding()
                                                .background(Color.blue.opacity(0.8))
                                                .cornerRadius(12)
                                                .foregroundColor(.white)
                                                .shadow(radius: 3)
                                        } else {
                                            Text(message.text)
                                                .padding()
                                                .background(Color.white.opacity(0.2))
                                                .cornerRadius(12)
                                                .foregroundColor(.white)
                                                .shadow(radius: 3)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        .padding()

                        HStack {
                            TextField(NSLocalizedString("message_placeholder", comment: ""), text: $inputText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding()
                                .frame(height: 50)
                                .background(Color.white)
                                .cornerRadius(10)
                                .foregroundColor(.black)

                            Button(action: sendMessage) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .shadow(radius: 3)
                            }
                        }

                        .padding()

                        Button(action: { showReminderList = true }) {
                            Text(NSLocalizedString("show_reminder_list", comment: ""))
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .shadow(radius: 3)
                        }
                        .padding()
                    }
                    .navigationTitle(NSLocalizedString("reminder_bot_title", comment: ""))
                    .onAppear {
                        loadReminders()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            filterValidReminders()
                        }
                        NotificationHandler.shared.requestAuthorization()
                    }
                    .onChange(of: notificationHandler.showSnoozeView) { _, _ in
                        if notificationHandler.showSnoozeView, let reminder = notificationHandler.snoozeReminder {
                            self.snoozeReminder = reminder
                            self.showSnoozeView = true
                            notificationHandler.showSnoozeView = false
                        }
                    }
                    .sheet(isPresented: $showReminderList) {
                        ReminderListView(reminders: $reminders, updateReminder: updateReminder)
                    }
                    .sheet(isPresented: $showSnoozeView) {
                        if let reminder = snoozeReminder {
                            SnoozeView(reminder: reminder, updateReminder: updateReminder)
                        }
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
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ 空のメッセージは送信できません")
            return
        }
        
        let userMessage = Message(text: inputText, isUser: true)
        messages.append(userMessage)

        let input = inputText // ユーザーの入力を保存
        inputText = "" // すぐにクリアして UI を更新

        DispatchQueue.main.async {
            if lastUserInput.isEmpty {
                lastUserInput = input
                let botPromptMessage = Message(
                    text: String(format: NSLocalizedString("reminder_prompt", comment: ""), input),
                    isUser: false
                )
                messages.append(botPromptMessage)
            } else if let date = extractDateTime(from: input) {
                let now = Date()
                if date < now {
                    let botPastDateMessage = Message(
                        text: NSLocalizedString("past_date_error", comment: ""),
                        isUser: false
                    )
                    messages.append(botPastDateMessage)
                } else {
                    let reminder = Reminder(text: lastUserInput, date: date)
                    reminders.append(reminder) // リストに追加
                    saveReminders() // 永続化
                    
                    let botConfirmationMessage = Message(
                        text: String(format: NSLocalizedString("reminder_set", comment: ""), formatDate(date)),
                        isUser: false
                    )
                    messages.append(botConfirmationMessage)
                    scheduleNotification(at: date, message: lastUserInput)
                    lastUserInput = "" // **リマインダーがセットされた場合のみクリア**
                }
            } else {
                let botErrorMessage = Message(
                    text: NSLocalizedString("unknown_date_error", comment: ""),
                    isUser: false
                )
                messages.append(botErrorMessage)
            }
        }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
    
    func extractDateTime(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)

        print("📥 入力テキスト: \(text)")

        var dateFound = false

        // **日付の抽出**
        let datePatterns = [
            "\\d{4}/\\d{1,2}/\\d{1,2}",
            "\\d{1,2}/\\d{1,2}",
            "\\d{1,2}月\\d{1,2}日",
            "\\d{4}年\\d{1,2}月\\d{1,2}日",
            "今日|きょう|today",
            "明日|あした|tomorrow",
            "明後日|あさって|day after tomorrow",
            "明々後日|three days later"
        ]

        for pattern in datePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let matchedDate = String(text[match])
                print("📅 マッチした日付: \(matchedDate)")

                let dateFormats = ["yyyy/M/d", "yyyy年M月d日", "M/d"]
                for format in dateFormats {
                    formatter.dateFormat = format
                    if let parsedDate = formatter.date(from: matchedDate) {
                        if format == "M/d" {
                            components.year = calendar.component(.year, from: now)
                        } else {
                            components.year = calendar.component(.year, from: parsedDate)
                        }
                        components.month = calendar.component(.month, from: parsedDate)
                        components.day = calendar.component(.day, from: parsedDate)
                        dateFound = true
                        break
                    }
                }
                break
            }
        }

        // **時間の抽出**
        let timePatterns = [
            "\\b\\d{1,2}:\\d{2}\\s?(am|pm|a\\.m\\.|p\\.m\\.)\\b", // 10:30 pm
            "\\b\\d{1,2}\\s?(am|pm|a\\.m\\.|p\\.m\\.)\\b", // 5pm, 10 a.m.
            "midnight",
            "noon",
            "in \\d+ minutes",
            "in \\d+ hours",
            "\\d{1,2}時間後",
            "\\d{1,2}分後"
        ]

        var foundTime = false
        var isPM = false
        var isAM = false

        for pattern in timePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                var matchedTime = String(text[match])
                matchedTime = matchedTime.replacingOccurrences(of: "：", with: ":") // 全角対応

                print("⏰ マッチした時間: \(matchedTime)")

                if matchedTime == "midnight" {
                    components.hour = 0
                    components.minute = 0
                    foundTime = true
                    break
                } else if matchedTime == "noon" {
                    components.hour = 12
                    components.minute = 0
                    foundTime = true
                    break
                }

                // **AM/PM表記の変換**
                if matchedTime.contains("p.m.") || matchedTime.contains("pm") || matchedTime.contains("PM") {
                    isPM = true
                } else if matchedTime.contains("a.m.") || matchedTime.contains("am") || matchedTime.contains("AM") {
                    isAM = true
                }

                // **フォーマット修正**
                matchedTime = matchedTime.replacingOccurrences(of: "p.m.", with: " PM")
                                         .replacingOccurrences(of: "a.m.", with: " AM")
                                         .replacingOccurrences(of: "pm", with: " PM")
                                         .replacingOccurrences(of: "am", with: " AM")
                                         .trimmingCharacters(in: .whitespaces)

                print("🔄 変換後の時間表記: \(matchedTime)")

                // **h:mm a に対応**
                if matchedTime.contains(":") {
                    formatter.dateFormat = "h:mm a"
                } else {
                    formatter.dateFormat = "h a"
                }

                if let parsedTime = formatter.date(from: matchedTime) {
                    var hour = calendar.component(.hour, from: parsedTime)
                    let minute = calendar.component(.minute, from: parsedTime)

                    print("🕒 解析前の時間: \(hour):\(minute) isPM: \(isPM) isAM: \(isAM)")

                    if isPM && hour < 12 {
                        hour += 12
                    } else if isAM && hour == 12 {
                        hour = 0
                    }

                    components.hour = hour
                    components.minute = minute
                    foundTime = true

                    print("✅ 変換後の時間: \(components.hour!):\(components.minute!)")
                    break
                } else {
                    print("⚠️ 時間の解析に失敗しました: \(matchedTime)")
                }
            }
        }

        // **日付が見つからず、時間だけ指定された場合は今日の日付を使用**
        if !dateFound && foundTime {
            print("📅 日付が見つからなかったため、今日の日付を使用")
            components.year = calendar.component(.year, from: now)
            components.month = calendar.component(.month, from: now)
            components.day = calendar.component(.day, from: now)
        }

        if !foundTime {
            components.hour = 9
            components.minute = 0
            print("⏳ 時間が見つからなかったため、デフォルト 9:00 を設定")
        }

        var localCalendar = Calendar.current
        localCalendar.timeZone = TimeZone.current
        var extractedDate = localCalendar.date(from: components)

        if let date = extractedDate {
            let timezoneDate = localCalendar.date(bySettingHour: components.hour!, minute: components.minute!, second: 0, of: date)
            print("📅 最終変換された日時: \(formatter.string(from: timezoneDate!))")
            return timezoneDate
        }

        print("❌ 変換に失敗しました")
        return nil
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
        content.title = NSLocalizedString("reminder_title", comment: "")
        content.body = message
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        // **デバッグログを出力**
        print("📅 スケジュールされた通知: \(formatDate(date))") // ← ここで 17:00 になっているか確認

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
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
