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
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(reminders) { reminder in
                    VStack(alignment: .leading) {
                        Text(reminder.text)
                            .font(.headline)
                        Text(formatDate(reminder.date))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .onDelete(perform: deleteReminder) // スワイプで削除
            }
            .navigationTitle("リマインダー一覧")
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
            cancelNotification(for: reminder) // 通知も削除
        }
        reminders.remove(atOffsets: offsets)
        saveReminders() // 永続化
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
