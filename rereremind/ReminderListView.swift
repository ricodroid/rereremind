//
//  ReminderListView.swift
//  rereremind
//
//  Created by riko on 2025/02/27.
//
import SwiftUI
import UserNotifications

struct ReminderListView: View {
    @Binding var reminders: [Reminder]
    var updateReminder: (Reminder, Date) -> Void // 🔹 `updateReminder` を受け取る

    @State private var selectedReminder: Reminder?

    var body: some View {
        NavigationStack {
            List {
                ForEach(reminders) { reminder in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(reminder.text)
                                .font(.headline)
                            Text(formatDate(reminder.date)) // 🔹 延長後の時間が表示されるように修正
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Button("延長") {
                            selectedReminder = reminder
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .onDelete(perform: deleteReminder)
            }
            .navigationTitle("リマインダー一覧")
            .sheet(item: $selectedReminder) { reminder in
                SnoozeView(reminder: reminder, updateReminder: updateReminder) // 🔹 `updateReminder` を渡す
            }
        }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    func deleteReminder(at offsets: IndexSet) {
        for index in offsets {
            let reminder = reminders[index]
            cancelNotification(for: reminder)
        }
        reminders.remove(atOffsets: offsets)
        saveReminders()
    }

    func cancelNotification(for reminder: Reminder) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            for request in requests {
                if request.content.body == reminder.text {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    print("通知削除: \(request.identifier)")
                }
            }
        }
    }

    func saveReminders() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(reminders) {
            UserDefaults.standard.set(encoded, forKey: "savedReminders")
        }
    }
}
