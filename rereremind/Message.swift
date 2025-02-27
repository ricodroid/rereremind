//
//  Message.swift
//  rereremind
//
//  Created by riko on 2025/02/24.
//

import SwiftUI
import UserNotifications

struct Message: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}
