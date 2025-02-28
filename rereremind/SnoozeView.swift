//
//  SnoozeView.swift
//  rereremind
//
//  Created by riko on 2025/02/27.
//
import SwiftUI
import UserNotifications

struct SnoozeView: View {
    @Environment(\.dismiss) var dismiss
    var reminder: Reminder
    var updateReminder: (Reminder, Date) -> Void // 🔹 `updateReminder` クロージャを追加

    let snoozeOptions: [(title: String, minutes: Int)] = [
        ("10分後に再通知", 10),
        ("1時間後に再通知", 60),
        ("2時間後に再通知", 120),
        ("3時間後に再通知", 180),
        ("明日の同じ時間に再通知", 1440),
        ("2日後の同じ時間に再通知", 2880),
        ("3日後の同じ時間に再通知", 4320),
        ("1週間後の同じ時間に再通知", 10080)
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(snoozeOptions, id: \.minutes) { option in
                    Button(action: {
                        let newDate = Calendar.current.date(byAdding: .minute, value: option.minutes, to: reminder.date) ?? reminder.date
                        scheduleSnoozedNotification(at: newDate, message: reminder.text)
                        updateReminder(reminder, newDate)
                        dismiss()
                    }) {
                        Text(option.title)
                            .padding()
                    }
                }
            }
            .navigationTitle("通知を延長")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    func scheduleSnoozedNotification(at date: Date, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "リマインダー"
        content.body = message
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("再通知のスケジュールに失敗: \(error.localizedDescription)")
            }
        }
    }
}
