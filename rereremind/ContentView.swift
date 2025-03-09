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
                                                .padding() // ユーザー側の吹き出し
                                                .background(Color.blue.opacity(0.9))
                                                .cornerRadius(12)
                                                .foregroundColor(.white)
                                                .shadow(radius: 3)
                                        } else {
                                            Text(message.text)
                                                .padding()
                                                .background(Color.white.opacity(0.9))
                                                .cornerRadius(12)
                                                .foregroundColor(.black)
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
                                .onSubmit {
                                    sendMessage()
                                }

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
                    }.onTapGesture {
                        hideKeyboard() // 🔹 画面タップ時にキーボードを閉じる
                    }
                    .navigationTitle(NSLocalizedString("reminder_bot_title", comment: ""))
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button(action: { showReminderList = true }) {
                                    Label(NSLocalizedString("show_reminder_list", comment: ""), systemImage: "list.bullet")
                                }
                                Divider()
                            } label: {
                                Image(systemName: "line.horizontal.3")
                                    .imageScale(.large)
                                    .foregroundColor(.primary)
                                    .padding(10)
                                    .background(Circle().fill(Color.blue.opacity(0.2)))
                                    .shadow(radius: 3)
                                    .animation(.easeInOut, value: showReminderList)
                            }
                        }
                    }
                    .onAppear {
                        DispatchQueue.global(qos: .userInitiated).async {
                            self.loadReminders()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.filterValidReminders()
                            }
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
        
        let input = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { self.inputText = "" }

        let userMessage = Message(text: inputText, isUser: true)
        messages.append(userMessage)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let now = Date()

            // 🔹 `lastUserInput` にリマインド内容がある場合 → 日付または時間を期待
            if !lastUserInput.isEmpty {
                if let date = extractDateTime(from: input) {
                    if date < now {
                        let botPastDateMessage = Message(
                            text: NSLocalizedString("past_date_error", comment: ""),
                            isUser: false
                        )
                        inputText = ""
                        lastUserInput = ""
                        messages.append(botPastDateMessage)
                        print("⚠️ 過去の日時が入力されたため、再入力を促す")
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
                        inputText = ""
                        lastUserInput = "" // **リマインダーがセットされた場合のみクリア**
                    }
                } else {
                    let botErrorMessage = Message(
                        text: NSLocalizedString("unknown_date_error", comment: ""),
                        isUser: false
                    )
                    messages.append(botErrorMessage)
                    inputText = ""
                    lastUserInput = "" 
                    print("⚠️ 有効な日付・時間が入力されなかったため、再入力を促す")
                }
            }
            // 🔹 `lastUserInput` が空 → ユーザーがリマインド内容を入力
            else {
                lastUserInput = input
                let botPromptMessage = Message(
                    text: String(format: NSLocalizedString("reminder_prompt", comment: "%@ Got it! When should I remind you?"), input),
                    isUser: false
                )
                messages.append(botPromptMessage)
            }
        }
    }


    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    func extractDateTime(from text: String) -> Date? {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)

        var dateFound = false
        if let extractedDate = extractDate(from: text, now: now) {
            components.year = calendar.component(.year, from: extractedDate)
            components.month = calendar.component(.month, from: extractedDate)
            components.day = calendar.component(.day, from: extractedDate)
            dateFound = true
        }

        var foundTime = false
        if let extractedTime = extractTime(from: text) {
            components.hour = extractedTime.hour
            components.minute = extractedTime.minute
            foundTime = true
        }

        // 🔹 日付のみ指定された場合 → その日の 9:00 AM に設定
        if dateFound && !foundTime {
            components.hour = 9
            components.minute = 0
        }
        // 🔹 時間のみ指定された場合 → 今の時間と比較し、一番近いその時間に設定
        else if !dateFound && foundTime {
            let extractedTime = calendar.date(from: components) ?? now
            if extractedTime < now {
                // 今の時間を過ぎていたら翌日に設定
                components.day! += 1
            }
        }

        return calendar.date(from: components)
    }


    func extractDate(from text: String, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        let calendar = Calendar.current
        var extractedDate: Date?
        
        // 🔹 入力テキストを正規化（小文字化 + 半角変換）
        let normalizedText = text.lowercased()
            .replacingOccurrences(of: "　", with: " ") // 全角スペースを半角スペースに変換
            .replacingOccurrences(of: "／", with: "/") // 全角スラッシュを半角スラッシュに変換
            .replacingOccurrences(of: "．", with: ".") // 全角ピリオドを半角ピリオドに変換
            .replacingOccurrences(of: "：", with: ":") // 全角コロンを半角コロンに変換
            .replacingOccurrences(of: "年", with: "/") // "2024年5月1日" → "2024/5/1"
            .replacingOccurrences(of: "月", with: "/") // "5月1日" → "5/1"
            .replacingOccurrences(of: "(?<=\\d)日", with: "", options: .regularExpression) // "5/1日" → "5/1"
        
        // 🔹 自然言語の日付パターン
        let datePatterns: [String: Int] = [
            "今日|きょう|today": 0,  // 今日
            "明日|あした|tomorrow": 1,  // 明日
            "明後日|あさって|day after tomorrow": 2,  // 明後日
            "昨日|きのう|yesterday": -1,  // 昨日（無視）
            "一昨日|おととい|two days ago": -2 // 一昨日（無視）
        ]
        print("🔍 正規化後のテキスト: \(normalizedText)")
        if normalizedText.contains("明日") {
            print("✅ 明日を検出！（contains() でマッチ）")
        }
        
        for (pattern, offset) in datePatterns {
            print("🔍 チェック: \(pattern) に \(normalizedText) がマッチするか？")

            if let matchRange = normalizedText.range(of: pattern, options: .regularExpression) {
                let matchedText = String(normalizedText[matchRange])
                print("📅 マッチした日付ワード: \(matchedText) (offset: \(offset))")

                extractedDate = calendar.date(byAdding: .day, value: offset, to: now)
                if offset >= 0 { // 過去の日付は無視
                    print("📅 解析した日付: \(extractedDate!)")
                    return extractedDate
                }
            }
        }

        // 🔹 数字での日付指定パターン（yyyy/MM/dd, MM/dd）
        let dateRegexPatterns = [
            "\\d{4}/\\d{1,2}/\\d{1,2}", // 2025/05/01
            "\\d{1,2}/\\d{1,2}",        // 5/1
        ]
        
        for pattern in dateRegexPatterns {
            if let match = normalizedText.range(of: pattern, options: .regularExpression) {
                let matchedDate = String(normalizedText[match])
                print("📅 マッチした日付: \(matchedDate)")

                let dateFormats = ["yyyy/M/d", "M/d"]
                for format in dateFormats {
                    formatter.dateFormat = format
                    if let parsedDate = formatter.date(from: matchedDate) {
                        // 年が指定されていない（例: "5/1"）場合は今年と判断
                        if format == "M/d" {
                            let currentYear = calendar.component(.year, from: now)
                            var dateComponents = calendar.dateComponents([.month, .day], from: parsedDate)
                            dateComponents.year = currentYear
                            extractedDate = calendar.date(from: dateComponents)
                        } else {
                            extractedDate = parsedDate
                        }
                        print("📅 解析後の確定日付: \(extractedDate!)")
                        return extractedDate
                    }
                }
            }
        }

        return nil
    }


    func extractTime(from text: String) -> (hour: Int, minute: Int)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        let timePatterns = [
            "\\b\\d{1,2}:\\d{2}\\b",
            "\\b\\d{1,2}:\\d{2}\\s?(am|pm|a\\.m\\.|p\\.m\\.)\\b",
            "\\b\\d{1,2}\\s?(am|pm|a\\.m\\.|p\\.m\\.)\\b",
            "midnight",
            "noon"
        ]
        
        var isPM = false
        var isAM = false
        
        for pattern in timePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                var matchedTime = String(text[match]).trimmingCharacters(in: .whitespaces)
                print("⏰ マッチした時間: \(matchedTime)")
                
                switch matchedTime {
                case "midnight":
                    return (0, 0)
                case "noon":
                    return (12, 0)
                default:
                    if matchedTime.contains("p.m.") || matchedTime.contains("pm") {
                        isPM = true
                    } else if matchedTime.contains("a.m.") || matchedTime.contains("am") {
                        isAM = true
                    }
                    
                    matchedTime = matchedTime.replacingOccurrences(of: "p.m.", with: " PM")
                                             .replacingOccurrences(of: "a.m.", with: " AM")
                                             .replacingOccurrences(of: "pm", with: " PM")
                                             .replacingOccurrences(of: "am", with: " AM")
                                             .trimmingCharacters(in: .whitespaces)
                    
                    print("🔄 変換後の時間表記: \(matchedTime)")
                    
                    formatter.dateFormat = matchedTime.contains(":") ? (matchedTime.contains("AM") || matchedTime.contains("PM") ? "h:mm a" : "HH:mm") : "h a"
                    
                    if let parsedTime = formatter.date(from: matchedTime) {
                        let calendar = Calendar.current
                        var hour = calendar.component(.hour, from: parsedTime)
                        let minute = calendar.component(.minute, from: parsedTime)
                        
                        print("🕒 解析前の時間: \(hour):\(minute) isPM: \(isPM) isAM: \(isAM)")
                        hour = convertTo24HourFormat(hour: hour, isPM: isPM, isAM: isAM)
                        
                        print("✅ 変換後の時間: \(hour):\(minute)")
                        return (hour, minute)
                    } else {
                        print("⚠️ 時間の解析に失敗しました: \(matchedTime)")
                    }
                }
            }
        }
        return nil
    }

    func convertTo24HourFormat(hour: Int, isPM: Bool, isAM: Bool) -> Int {
        if isPM && hour < 12 {
            return hour + 12
        } else if isAM && hour == 12 {
            return 0
        }
        return hour
    }


    func loadReminders() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let savedData = UserDefaults.standard.data(forKey: remindersKey) {
                let decoder = JSONDecoder()
                if let loadedReminders = try? decoder.decode([Reminder].self, from: savedData) {
                    DispatchQueue.main.async {
                        self.reminders = loadedReminders
                    }
                }
            }
        }
    }
    
    func filterValidReminders() {
        DispatchQueue.global(qos: .background).async {
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let requestBodies = requests.map { $0.content.body }
                
                DispatchQueue.main.async {
                    self.reminders = self.reminders.filter { reminder in
                        requestBodies.contains(reminder.text)
                    }
                    self.saveReminders()
                }
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

    // 🔹 キーボードを閉じる処理
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    ContentView()
}
