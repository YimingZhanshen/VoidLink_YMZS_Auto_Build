//
//  GameSirG8MFiRumble.h
//  VoidLink
//

#import <Foundation/Foundation.h>
#include <stdint.h>

@class GCController;

NS_ASSUME_NONNULL_BEGIN

@interface GameSirG8MFiRumble : NSObject

- (BOOL)canHandleController:(GCController *)controller;
- (BOOL)isTargetController:(GCController *)controller;
- (void)setLowFrequencyMotor:(uint16_t)lowFrequencyMotor highFrequencyMotor:(uint16_t)highFrequencyMotor;
- (void)stopAndClose;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
