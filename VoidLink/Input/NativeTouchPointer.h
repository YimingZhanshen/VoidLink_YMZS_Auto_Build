//
//  NativeTouchPointer.h
//  VoidLink
//
//  Created by True砖家 on 2024/5/14.
//  Copyright © 2024 True砖家 on Bilibili. All rights reserved.
//

#import "StreamView.h"
#import "NativeTouchHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface NativeTouchPointer : NSObject
@property (nonatomic, assign) bool needResetCoords;
@property (nonatomic, assign) CGPoint initialPoint;
@property (nonatomic, assign) CGPoint latestPoint;
@property (nonatomic, assign) CGPoint previousPoint;
@property (nonatomic, assign) CGPoint latestRelativePoint;
@property (nonatomic, assign) CGPoint previousRelativePoint;
@property (nonatomic, assign) bool useRelativeCoords;


+ (void)initContextWithView:(StreamView*)view profile:(OSCProfile*)profile;
+ (void)cleanUpContext;

- (bool)doesNeedResetCoords;
- (void)updatePointerCoords:(UITouch *)touch;


// Explicit view and gain let trackpad input reuse the mapping without global context.
- (instancetype)initWithTouch:(UITouch *)touch view:(StreamView *)view NS_SWIFT_NAME(init(touch:view:));
- (void)updatePointerCoords:(UITouch *)touch inView:(StreamView *)view velocityFactor:(CGFloat)velocityFactor NS_SWIFT_NAME(update(touch:in:velocityFactor:));

- (instancetype)initWithTouch:(UITouch *)touch;
@end




NS_ASSUME_NONNULL_END

