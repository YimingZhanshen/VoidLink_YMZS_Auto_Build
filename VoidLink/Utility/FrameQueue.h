//
//  FrameQueue.h
//  Moonlight
//
//  Created by Andy Grundman.
//  Ported to VoidLink by Acaki.
//  Copyright (c) 2025 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2026/8/12.
//  Copyright © 2026 True砖家 on Bilibili. All rights reserved.
//
//


#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#import "Frame.h"
#import "FloatBuffer.h"

NS_ASSUME_NONNULL_BEGIN

@interface FrameQueue : NSObject

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic) FloatBuffer *frameDropMetrics;
@property (nonatomic) int highWaterMark;
@property (nonatomic, readonly) int maxCapacity;
@property (atomic) BOOL paused;
- (void)dequeueWithTimeout:(CFTimeInterval)timeout
                completion:(void (^)(Frame *frame))completion;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (BOOL)isEmpty;
- (void)clear;
- (int)enqueue:(Frame *)frame;
- (int)enqueue:(Frame *)frame withSlackSize:(int)slack;
- (nullable Frame *)dequeue;
- (nullable Frame *)dequeueWithTimeoutSync:(CFTimeInterval)timeout;
- (CFTimeInterval)estimatedFramerate;
- (int)currentSoftCap;
- (void)waitForEnqueue;
- (void)startForOwner:(id)owner;
- (void)stopForOwner:(id)owner;

@end

NS_ASSUME_NONNULL_END
