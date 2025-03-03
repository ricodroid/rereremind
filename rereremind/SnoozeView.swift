//
//  SnoozeView.swift
//  rereremind
//
//  Created by riko on 2025/02/27.
//
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
        (NSLocalizedString("snooze_10_minutes", comment: ""), 10),
        (NSLocalizedString("snooze_1_hour", comment: ""), 60),
        (NSLocalizedString("snooze_2_hours", comment: ""), 120),
        (NSLocalizedString("snooze_3_hours", comment: ""), 180),
        (NSLocalizedString("snooze_tomorrow_same_time", comment: ""), 1440),
        (NSLocalizedString("snooze_2_days_later", comment: ""), 2880),
        (NSLocalizedString("snooze_3_days_later", comment: ""), 4320),
        (NSLocalizedString("snooze_1_week_later", comment: ""), 10080)
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
            .navigationTitle(NSLocalizedString("snooze_title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("close", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }

    func scheduleSnoozedNotification(at date: Date, message: String) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("reminder_title", comment: "")
        content.body = message
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print(NSLocalizedString("schedule_error", comment: "") + " \(error.localizedDescription)")
            }
        }
    }
}
