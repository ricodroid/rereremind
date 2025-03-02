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
            let botPromptMessage = Message(
                text: String(format: NSLocalizedString("reminder_prompt", comment: ""), inputText),
                isUser: false
            )
            messages.append(botPromptMessage)
        } else if let date = extractDateTime(from: inputText) {
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
                lastUserInput = ""
            }
        } else {
            let botErrorMessage = Message(
                text: NSLocalizedString("unknown_date_error", comment: ""),
                isUser: false
            )
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
        formatter.locale = Locale(identifier: "en_US_POSIX") // 日本語と英語の両方に対応
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)

        // **日付の抽出**
        let datePatterns = [
            "\\d{4}/\\d{1,2}/\\d{1,2}",         // 2025/5/1, 2026/1/1
            "\\d{1,2}/\\d{1,2}",                // 5/1
            "\\d{1,2}月\\d{1,2}日",            // 5月1日
            "\\d{4}年\\d{1,2}月\\d{1,2}日",    // 2025年5月1日
            "今日|きょう|today|Today|TODAY",
            "明日|あした|tomorrow|Tomorrow|TOMORROW",
            "明後日|あさって|day after tomorrow|Day after tomorrow|DAY AFTER TOMORROW|2 days later",
            "明々後日|three days later|Three days later|THREE DASY LATER|3 days later"
        ]

        var dateMatched = false
        for pattern in datePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let matchedDate = String(text[match])
                if ["今日", "きょう", "today", "Today", "TODAY"].contains(matchedDate) {
                    // 今日（変更なし）
                } else if ["明日", "あした", "tomorrow", "Tomorrow", "TOMORROW"].contains(matchedDate) {
                    components.day! += 1
                } else if ["明後日", "あさって", "day after tomorrow", "Day after tomorrow", "DAY AFTER TOMORROW", "2 days later"].contains(matchedDate) {
                    components.day! += 2
                } else if ["明々後日", "three days later", "Three days later", "THREE DASY LATER", "3 days later"].contains(matchedDate) {
                    components.day! += 3
                } else {
                    let dateFormats = ["yyyy/M/d", "yyyy年M月d日", "M/d", "MM/dd", "MMMM d", "MMMM d, yyyy"]
                    for format in dateFormats {
                        formatter.dateFormat = format
                        if let parsedDate = formatter.date(from: matchedDate) {
                            components.year = calendar.component(.year, from: parsedDate)
                            components.month = calendar.component(.month, from: parsedDate)
                            components.day = calendar.component(.day, from: parsedDate)
                            dateMatched = true
                            break
                        }
                    }
                }
                dateMatched = true
                break
            }
        }

        // **時間の抽出**
        let timePatterns = [
            "\\d{1,2}:\\d{2}",           // 9:00, 21:30
            "\\d{1,2}時",                // 9時, 21時 (日本語)
            "\\d{1,2}：\\d{2}",          // ９：００（全角対応）
            "\\d{1,2}:\\d{2} (am|pm)",   // 9:00 am, 10:30 pm
            "\\d{1,2} (am|pm)",          // 5pm, 1am
            "\\d{1,2}",                  // 5, 22（数字だけでも時刻として解釈）
            "quarter past \\d{1,2}",     // quarter past 3 → 3:15
            "half past \\d{1,2}",        // half past 6 → 6:30
            "quarter to \\d{1,2}",       // quarter to 10 → 9:45
            "midnight",                  // midnight → 0:00
            "noon",                      // noon → 12:00
            "in \\d+ minutes",           // in 15 minutes → 現在時刻 + 15分
            "in \\d+ hours",             // in 3 hours → 現在時刻 + 3時間
            "at \\d{1,2} o’clock",       // at 5 o’clock → 17:00
            "by \\d{1,2} (am|pm)"        // by 10 PM → 22:00
        ]

        var foundTime = false
        for pattern in timePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                var matchedTime = String(text[match]).replacingOccurrences(of: "：", with: ":") // 全角対応

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
                } else if matchedTime.contains("quarter past") {
                    if let hour = Int(matchedTime.replacingOccurrences(of: "quarter past ", with: "")) {
                        components.hour = hour
                        components.minute = 15
                        foundTime = true
                        break
                    }
                } else if matchedTime.contains("half past") {
                    if let hour = Int(matchedTime.replacingOccurrences(of: "half past ", with: "")) {
                        components.hour = hour
                        components.minute = 30
                        foundTime = true
                        break
                    }
                } else if matchedTime.contains("quarter to") {
                    if let hour = Int(matchedTime.replacingOccurrences(of: "quarter to ", with: "")) {
                        components.hour = hour - 1
                        components.minute = 45
                        foundTime = true
                        break
                    }
                } else if matchedTime.contains("in") {
                    let timeValue = Int(matchedTime.components(separatedBy: " ")[1]) ?? 0
                    if matchedTime.contains("minutes") {
                        components.minute! += timeValue
                    } else if matchedTime.contains("hours") {
                        components.hour! += timeValue
                    }
                    foundTime = true
                    break
                } else if matchedTime.contains("o’clock") {
                    let hourString = matchedTime.replacingOccurrences(of: " o’clock", with: "")
                    if let hour = Int(hourString) {
                        components.hour = hour
                        components.minute = 0
                        foundTime = true
                        break
                    }
                } else {
                    // **標準的な時間解析**
                    var isPM = matchedTime.lowercased().contains("pm")
                    var isAM = matchedTime.lowercased().contains("am")

                    // "5pm" → "5 PM" など、正しいフォーマットにする
                    matchedTime = matchedTime.uppercased().trimmingCharacters(in: .whitespaces)

                    if isPM || isAM {
                        formatter.dateFormat = "h a" // 12時間表記 ("5 PM" → 17:00)
                    } else if matchedTime.contains(":") {
                        formatter.dateFormat = "H:mm" // 24時間表記
                    } else {
                        matchedTime += ":00"
                        formatter.dateFormat = "H:mm"
                    }

                    if let parsedTime = formatter.date(from: matchedTime) {
                        var hour = calendar.component(.hour, from: parsedTime)
                        let minute = calendar.component(.minute, from: parsedTime)

                        // **PMなら+12時間する**
                        if isPM && hour != 12 {
                            hour += 12
                        } else if isAM && hour == 12 {
                            hour = 0 // 午前12時（midnight）なら 0 に変換
                        }

                        // **hourを components に適用**
                        components.hour = hour
                        components.minute = minute

                        print("⏰ 抽出された時間: \(hour):\(minute)") // ← デバッグログで確認

                        foundTime = true
                        break
                    }

                }
            }
        }

        // **時間が見つからない場合はデフォルトを 9:00 に設定**
        if !foundTime {
            components.hour = 9
            components.minute = 0
        }

        // **最終的な日付を作成**
        var localCalendar = Calendar.current
        localCalendar.timeZone = TimeZone.current // ローカルタイムゾーンを適用
        var extractedDate = localCalendar.date(from: components)

        // **PM の場合は 12 時間足す**
        if let hour = components.hour, hour < 12, text.lowercased().contains("pm") {
            components.hour = hour + 12
            extractedDate = localCalendar.date(from: components)
        }

        // **現在のタイムゾーンを考慮して UTC にならないようにする**
        if let date = extractedDate {
            let timezoneDate = localCalendar.date(bySettingHour: components.hour!, minute: components.minute!, second: 0, of: date)

            print("⏰ 抽出された時間: \(components.hour!):\(components.minute!)") // デバッグログ
            print("📅 タイムゾーン調整後の日時: \(formatDate(timezoneDate!))") // デバッグログ

            if timezoneDate! < now {
                return nil
            }

            return timezoneDate
        }

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
        content.title = "リマインダー"
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
