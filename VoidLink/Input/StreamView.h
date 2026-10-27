//
//  StreamView.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.6.16
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.


//

#import "ControllerSupport.h"
#import "OnScreenControls.h"
#import "StreamConfiguration.h"
#include <math.h>

@class PencilHandler;

// A single value keeps async input's viewport and fitted video area consistent.
typedef struct {
    CGRect bounds;
    CGRect videoRect;
} StreamInputGeometry;

NS_INLINE StreamInputGeometry StreamInputGeometryMake(CGRect bounds, CGFloat aspectRatio) {
    StreamInputGeometry geometry = { bounds, CGRectZero };
    if (!(aspectRatio > 0) || !isfinite(aspectRatio) || bounds.size.width <= 0 || bounds.size.height <= 0) {
        return geometry;
    }
    CGSize size = bounds.size.width > bounds.size.height * aspectRatio
        ? CGSizeMake(bounds.size.height * aspectRatio, bounds.size.height)
        : CGSizeMake(bounds.size.width, bounds.size.width / aspectRatio);
    geometry.videoRect = CGRectMake(CGRectGetMidX(bounds) - size.width / 2,
                                    CGRectGetMidY(bounds) - size.height / 2,
                                    size.width, size.height);
    return geometry;
}

@protocol UserInteractionDelegate <NSObject>

- (void)userInteractionBegan;
- (void)userInteractionEnded;
- (void)streamExitRequested;
- (void)toggleStatsOverlay;
- (void)toggleMouseCapture;
- (void)toggleMouseVisible;
- (void)expandSettingsView;
- (void)disconnectAndQuitApp;

@end

@interface StreamView : UIView

@property (weak, nonatomic) UIView* streamFrameTopLayerView;
@property (weak, nonatomic) id<UserInteractionDelegate> interactionDelegate;
@property (assign, nonatomic) CGFloat streamAspectRatio;
@property (assign, atomic, readonly) StreamInputGeometry inputGeometry;
@property (assign, nonatomic) CGRect originalFrame;
@property (assign, nonatomic) bool widgetToolOpened;
@property (strong, nonatomic) OnScreenControls* onScreenControls;
@property (weak, nonatomic) PencilHandler* pencilHandler;

- (void) setupStreamViewWithControllerSupport:(ControllerSupport*)controllerSupport
                          interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                                 streamConfig:(StreamConfiguration*)streamConfig
                                  gameProfile:(OSCProfile* )profile
                      streamFrameTopLayerView:(UIView* )topLayerView
;

- (void)cleanUp;

- (void) reloadLegacyWidgets:(OSCProfile* )profile;
- (void) setOnScreenControls;
- (void) disableOnScreenControls;
- (void) reloadOnScreenControlsRealtimeWithControllerSupport:(ControllerSupport*)controllerSupport
                          streamConfig:(StreamConfiguration*)streamConfig;
- (void) reloadOnScreenControlsWith:(ControllerSupport*)controllerSupport
                          andConfig:(StreamConfiguration*)streamConfig;
- (void) clearOnScreenWidgets;
- (void) reloadGameProfile:(OSCProfile* )profile reloadWidgets:(bool)reloadWidgets;
- (void) saveStreamingGameProfileChanges;
- (bool) isOnScreenWidgetEnabled;

- (CGSize) getVideoAreaSize;
- (CGPoint) adjustCoordinatesForVideoArea:(CGPoint)point;
- (uint16_t)getRotationFromAzimuthAngle:(float)azimuthAngle;

- (OnScreenControlsLevel) getCurrentOscState;

- (void)readyToBringUpSoftKeyboardByToolbox;
- (void)toggleSoftKeyboardFromButton;
- (void)remoteTextInputForTvOS;
- (void)keyboardWillShow:(NSNotification *)notification;
- (void)keyboardWillHide;
- (void)keyboardDidChangeFrame;
- (void)handleNonStandardKeyboard:(NSNotification *)notification;
- (void)liftMetalVideoViewIfNeeded:(CGFloat)liftHeight;

- (void)alterAbsTouchDragWith:(int32_t)mouseButton;

- (void)enablePencilHover;
- (void)disablePencilHover;
- (void)setAllowSingleTouchEnabled:(BOOL)enabled;
- (void)toggleTouchDisabled:(bool)disabled;

- (void)startInteractionTimer;

#if !TARGET_OS_TV
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse;
#endif

@end
