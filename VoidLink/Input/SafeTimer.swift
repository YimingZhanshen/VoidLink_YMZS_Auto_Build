//
//  SafeTimer.swift
//  VoidLink
//
//  Created by True砖家 on 2025/9/9.
//  Copyright © 2025 True砖家@Bilibili. All rights reserved.
//

import Foundation
import QuartzCore

@objc(SafeTimer)
final class SafeTimer: NSObject {
    private var timer: DispatchSourceTimer?
    private let timerQueue: DispatchQueue       // 私有串行队列
    private let timerQueueKey = DispatchSpecificKey<UInt8>()
    private let userHandler: () -> Void
    private let interval: TimeInterval
    private let delay: TimeInterval

    private var shouldRunHandler: Bool = false  // 控制逻辑上的暂停/恢复
    private var isCleaned: Bool = false         // 是否已经 clean
    @objc private(set) var remainingMinimumRunCount: Int = 0
    private var shouldCleanAfterMinimumRuns: Bool = false

    @objc init(interval: TimeInterval = 1.0,
         delay: TimeInterval = 0,
         queueLabel: String = "com.example.safetimer",
         handler: @escaping () -> Void) {
        
        self.interval = interval
        self.delay = delay
        self.userHandler = handler
        self.timerQueue = DispatchQueue(label: queueLabel)
        self.timerQueue.setSpecific(key: timerQueueKey, value: 1)
        
        super.init()

        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        t.schedule(deadline: .now() + delay, repeating: interval)

        t.setEventHandler { [weak self] in
            guard let self = self, !self.isCleaned else { return }
            if !self.shouldRunHandler { return }
            self.userHandler()
            if self.remainingMinimumRunCount > 0 {
                self.remainingMinimumRunCount -= 1
            }
            if self.shouldCleanAfterMinimumRuns && self.remainingMinimumRunCount == 0 {
                self.cleanOnTimerQueue(force: true)
            }
        }

        t.resume()  // timer 一开始就 resume，避免 suspend/resume 的计数问题
        self.timer = t
    }

    deinit {
        cleanForDeinit()
    }

    /// 开始逻辑上的计时
    @objc func start() {
        timerQueue.async { [weak self] in
            guard let self = self, !self.isCleaned else { return }
            self.shouldRunHandler = true
        }
    }

    /// 暂停逻辑上的计时
    @objc func pause() {
        timerQueue.async { [weak self] in
            guard let self = self, !self.isCleaned else { return }
            self.shouldRunHandler = false
        }
    }

    /// 重置下一次触发时间，并开始执行 handler
    @objc func restart() {
        restart(minimumRunCount: 1)
    }

    /// 重置下一次触发时间，并保证 clean 前至少执行 minimumRunCount 次 handler
    @objc(restartWithMinimumRunCount:)
    func restart(minimumRunCount: Int = 1) {
        timerQueue.async { [weak self] in
            guard let self = self, let t = self.timer, !self.isCleaned else { return }
            self.remainingMinimumRunCount = max(0, minimumRunCount)
            self.shouldCleanAfterMinimumRuns = false
            t.schedule(deadline: .now() + self.delay, repeating: self.interval)
            self.shouldRunHandler = true
        }
    }
    
    @objc func isRunning() -> Bool {
        if DispatchQueue.getSpecific(key: timerQueueKey) != nil {
            return shouldRunHandler
        }

        return timerQueue.sync {
            shouldRunHandler && !isCleaned
        }
    }

    /// 彻底清理 timer；如果 restart(minimumRunCount:) 尚未跑够次数，则延后到最低次数满足后清理
    @objc func clean() {
        if DispatchQueue.getSpecific(key: timerQueueKey) != nil {
            cleanOnTimerQueue()
            return
        }

        // 同步在 timerQueue 执行，保证已排队事件全部处理完（或跳过）
        timerQueue.sync {
            cleanOnTimerQueue()
        }
    }

    private func cleanForDeinit() {
        if DispatchQueue.getSpecific(key: timerQueueKey) != nil {
            cleanOnTimerQueue(force: true)
            return
        }

        timerQueue.sync {
            cleanOnTimerQueue(force: true)
        }
    }

    private func cleanOnTimerQueue(force: Bool = false) {
        guard !isCleaned else { return }
        if !force && shouldRunHandler && remainingMinimumRunCount > 0 {
            shouldCleanAfterMinimumRuns = true
            return
        }

        isCleaned = true
        shouldRunHandler = false
        remainingMinimumRunCount = 0
        shouldCleanAfterMinimumRuns = false

        if let t = timer {
            t.setEventHandler {}  // 清空 handler
            t.cancel()            // 取消 timer
            timer = nil
        }
    }
}
