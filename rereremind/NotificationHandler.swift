//
//  NotificationHandler.swift
//  rereremind
//
//  Created by riko on 2025/02/27.
//
import UserNotifications
import SwiftUI

class NotificationHandler: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NotificationHandler()
    
    @Published var snoozeReminder: Reminder? // 🔹 延長するリマインダーを保持
    @Published var showSnoozeView = false // 🔹 SnoozeViewを表示するフラグ
    var pendingReminder: Reminder? // 🔹 アプリが完全に閉じていた場合のための一時保存

    // 🔹 フォアグラウンドでも通知を表示する
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound]) // 🔹 通知のバナーとサウンドを許可
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let originalDate = Calendar.current.date(from: (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents ?? DateComponents()) ?? Date()
        let reminder = Reminder(text: request.content.body, date: originalDate)

        if response.actionIdentifier == "SNOOZE_ACTION" {
            DispatchQueue.main.async {
                print("🔔 通知アクションボタンがタップされました")
                self.snoozeReminder = reminder
                self.showSnoozeView = true
            }
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // 🔹 通知全体がタップされたときの処理
            DispatchQueue.main.async {
                print("📲 通知がタップされました - SnoozeView を開きます")
                self.snoozeReminder = reminder
                self.showSnoozeView = true
            }
        }
        completionHandler()
    }

    func applicationDidBecomeActive() {
        // 🔹 アプリがバックグラウンドから復帰したとき
        DispatchQueue.main.async {
            if let reminder = self.pendingReminder {
                print("📲 アプリ起動後、SnoozeView を開きます")
                self.snoozeReminder = reminder
                self.showSnoozeView = true
                self.pendingReminder = nil // 一度開いたらリセット
            }
        }
    }

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("通知の許可リクエスト失敗: \(error.localizedDescription)")
            }
        }
        
        // 🔹 通知の「延長」アクションを登録
        let snoozeAction = UNNotificationAction(identifier: "SNOOZE_ACTION", title: "通知を延長", options: [.foreground])
        let category = UNNotificationCategory(identifier: "REMINDER_CATEGORY", actions: [snoozeAction], intentIdentifiers: [], options: [])
        
        center.setNotificationCategories([category])
        center.delegate = self
    }
}
