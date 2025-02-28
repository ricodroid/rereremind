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
                .sheet(isPresented: $showReminderList) {
                    ReminderListView(reminders: $reminders)
                }
            }
            .navigationTitle("リマインダーBot")
            .onAppear {
                loadReminders()
                filterValidReminders()
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

        // 日付の正規表現
        let datePatterns = [
            "\\d{4}/\\d{1,2}/\\d{1,2}",  // 2025/5/1, 2026/1/1, 2027/02/01
            "\\d{1,2}/\\d{1,2}",         // 5/1
            "\\d{1,2}月\\d{1,2}日",     // 5月1日
            "\\d{4}年\\d{1,2}月\\d{1,2}日", // 2025年5月1日
            "今日|きょう", "明日|あした", "明後日|あさって", "明々後日"
        ]

        for pattern in datePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let matchedDate = String(text[match])
                if matchedDate.contains("今日") || matchedDate.contains("きょう") {
                    // 今日の日付
                } else if matchedDate.contains("明日") || matchedDate.contains("あした") {
                    components.day! += 1
                } else if matchedDate.contains("明後日") || matchedDate.contains("あさって") {
                    components.day! += 2
                } else if matchedDate.contains("明々後日") {
                    components.day! += 3
                } else {
                    formatter.dateFormat = "yyyy/M/d"
                    if let parsedDate = formatter.date(from: matchedDate) {
                        components.year = calendar.component(.year, from: parsedDate)
                        components.month = calendar.component(.month, from: parsedDate)
                        components.day = calendar.component(.day, from: parsedDate)
                        break
                    }

                    formatter.dateFormat = "yyyy年M月d日"
                    if let parsedDate = formatter.date(from: matchedDate) {
                        components.year = calendar.component(.year, from: parsedDate)
                        components.month = calendar.component(.month, from: parsedDate)
                        components.day = calendar.component(.day, from: parsedDate)
                        break
                    }

                    // ここを追加
                    formatter.dateFormat = "M/d"
                    if let parsedDate = formatter.date(from: matchedDate) {
                        components.year = calendar.component(.year, from: now) // 現在の年を適用
                        components.month = calendar.component(.month, from: parsedDate)
                        components.day = calendar.component(.day, from: parsedDate)
                        break
                    }

                    formatter.dateFormat = "MM/dd"
                    if let parsedDate = formatter.date(from: matchedDate) {
                        components.year = calendar.component(.year, from: now) // 現在の年を適用
                        components.month = calendar.component(.month, from: parsedDate)
                        components.day = calendar.component(.day, from: parsedDate)
                        break
                    }
                }

            }
        }

        // 時間の正規表現
        let timePatterns = [
            "\\d{1,2}:\\d{2}",      // 9:00, 21:30
            "\\d{1,2}時",            // 9時, 21時
            "\\d{1,2}：\\d{2}",    // ９：００
            "\\d{1,2}:\\d{2} (am|pm)" // 9:00 am
        ]

        var foundTime = false
        for pattern in timePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let matchedTime = String(text[match]).replacingOccurrences(of: "：", with: ":")
                formatter.dateFormat = "H:mm"
                if let parsedTime = formatter.date(from: matchedTime.replacingOccurrences(of: "時", with: ":00")) {
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

        // 修正: 現在より前の日付を避ける
        if let date = extractedDate, date < now {
            return nil
        }

        return extractedDate
    }
    
    func saveReminders() {
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(reminders) {
                UserDefaults.standard.set(encoded, forKey: remindersKey)
            }
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
                  self.reminders = self.reminders.filter { reminder in
                      requests.contains { $0.content.body == reminder.text }
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
