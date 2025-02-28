//
//  Reminder.swift
//  rereremind
//
//  Created by riko on 2025/02/27.
//

import Foundation

struct Reminder: Identifiable, Codable {
    var id = UUID()
    var text: String
    var date: Date
}
