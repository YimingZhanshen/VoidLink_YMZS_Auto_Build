//
//  HapticContext.m
//  Moonlight
//
//  Created by Cameron Gutman on 9/17/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//
//  Modified by True砖家 on 2025.10.12
//  Copyright © 2025 True砖家 @ Bilibili. All rights reserved.
//

#import "HapticContext.h"
#import "DataManager.h"

@import CoreHaptics;
@import GameController;

@implementation HapticContext {
    GCControllerPlayerIndex _playerIndex;
    CHHapticEngine* _hapticEngine API_AVAILABLE(ios(13.0), tvos(14.0));
    id<CHHapticPatternPlayer> _motorHapticPlayer API_AVAILABLE(ios(13.0), tvos(14.0));
    id<CHHapticPatternPlayer> _authoredHapticPlayer API_AVAILABLE(ios(13.0), tvos(14.0));
    BOOL _motorPlaying;
    BOOL _authoredPlaying;
}

-(void)cleanup API_AVAILABLE(ios(14.0), tvos(14.0)) {
    if (_motorHapticPlayer != nil) {
        [_motorHapticPlayer cancelAndReturnError:nil];
        _motorHapticPlayer = nil;
    }
    if (_authoredHapticPlayer != nil) {
        [_authoredHapticPlayer cancelAndReturnError:nil];
        _authoredHapticPlayer = nil;
    }
    if (_hapticEngine != nil) {
        [_hapticEngine stopWithCompletionHandler:nil];
        _hapticEngine = nil;
    }
}

-(void)setMotorAmplitude:(unsigned short)amplitude API_AVAILABLE(ios(14.0), tvos(14.0)) {
    NSError* error;

    // Check if the haptic engine died
    if (_hapticEngine == nil) {
        return;
    }
    
    // Stop the effect entirely if the amplitude is 0
    if (amplitude == 0) {
        if (_motorPlaying) {
            [_motorHapticPlayer stopAtTime:0 error:&error];
            _motorPlaying = NO;
        }
        
        return;
    }

    if (_motorHapticPlayer == nil) {
        // We must initialize the intensity to 1.0f because the dynamic parameters are multiplied by this value before being applied
        CHHapticEventParameter* intensityParameter = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:1.0f];
        CHHapticEvent* hapticEvent = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous parameters:[NSArray arrayWithObject:intensityParameter] relativeTime:0 duration:GCHapticDurationInfinite];
        CHHapticPattern* hapticPattern = [[CHHapticPattern alloc] initWithEvents:[NSArray arrayWithObject:hapticEvent] parameters:[[NSArray alloc] init] error:&error];
        if (error != nil) {
            Log(LOG_W, @"Controller %d: Haptic pattern creation failed: %@", _playerIndex, error);
            return;
        }
        
        _motorHapticPlayer = [_hapticEngine createPlayerWithPattern:hapticPattern error:&error];
        if (error != nil) {
            Log(LOG_W, @"Controller %d: Haptic player creation failed: %@", _playerIndex, error);
            return;
        }
    }

    CHHapticDynamicParameter* intensityParameter = [[CHHapticDynamicParameter alloc] initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:amplitude / 65535.0f relativeTime:0];
    [_motorHapticPlayer sendParameters:[NSArray arrayWithObject:intensityParameter] atTime:CHHapticTimeImmediate error:&error];
    if (error != nil) {
        Log(LOG_W, @"Controller %d: Haptic player parameter update failed: %@", _playerIndex, error);
        return;
    }
    
    if (!_motorPlaying) {
        [_motorHapticPlayer startAtTime:0 error:&error];
        if (error != nil) {
            _motorHapticPlayer = nil;
            Log(LOG_W, @"Controller %d: Haptic playback start failed: %@", _playerIndex, error);
            return;
        }
        
        _motorPlaying = YES;
    }
}

-(void)setAuthoredAmplitude:(float)amplitude
                  sharpness:(float)sharpness
          transientStrength:(float)transientStrength API_AVAILABLE(ios(14.0), tvos(14.0)) {
    if (_hapticEngine == nil) {
        return;
    }

    amplitude = fmaxf(0.0f, fminf(1.0f, amplitude));
    sharpness = fmaxf(0.0f, fminf(1.0f, sharpness));
    transientStrength = fmaxf(0.0f, fminf(1.0f, transientStrength));

    NSError* error = nil;
    if (amplitude == 0.0f) {
        if (_authoredPlaying) {
            [_authoredHapticPlayer stopAtTime:CHHapticTimeImmediate error:&error];
            _authoredPlaying = NO;
        }
    }
    else {
        if (_authoredHapticPlayer == nil) {
            CHHapticEventParameter* intensity = [[CHHapticEventParameter alloc]
                initWithParameterID:CHHapticEventParameterIDHapticIntensity value:1.0f];
            CHHapticEventParameter* eventSharpness = [[CHHapticEventParameter alloc]
                initWithParameterID:CHHapticEventParameterIDHapticSharpness value:0.5f];
            CHHapticEvent* event = [[CHHapticEvent alloc]
                initWithEventType:CHHapticEventTypeHapticContinuous
                parameters:@[intensity, eventSharpness]
                relativeTime:0
                duration:GCHapticDurationInfinite];
            CHHapticPattern* pattern = [[CHHapticPattern alloc]
                initWithEvents:@[event] parameters:@[] error:&error];
            if (pattern == nil || error != nil) {
                Log(LOG_W, @"Controller %d: Authored haptic pattern creation failed: %@", _playerIndex, error);
                return;
            }
            _authoredHapticPlayer = [_hapticEngine createPlayerWithPattern:pattern error:&error];
            if (_authoredHapticPlayer == nil || error != nil) {
                Log(LOG_W, @"Controller %d: Authored haptic player creation failed: %@", _playerIndex, error);
                return;
            }
        }

        NSArray* parameters = @[
            [[CHHapticDynamicParameter alloc]
                initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl
                value:amplitude relativeTime:0],
            [[CHHapticDynamicParameter alloc]
                initWithParameterID:CHHapticDynamicParameterIDHapticSharpnessControl
                value:sharpness relativeTime:0]
        ];
        [_authoredHapticPlayer sendParameters:parameters atTime:CHHapticTimeImmediate error:&error];
        if (error != nil) {
            Log(LOG_W, @"Controller %d: Authored haptic parameter update failed: %@", _playerIndex, error);
            return;
        }
        if (!_authoredPlaying) {
            [_authoredHapticPlayer startAtTime:CHHapticTimeImmediate error:&error];
            if (error != nil) {
                _authoredHapticPlayer = nil;
                Log(LOG_W, @"Controller %d: Authored haptic playback start failed: %@", _playerIndex, error);
                return;
            }
            _authoredPlaying = YES;
        }
    }

    // Emit one-shot attacks only when the analyzer found a meaningful transient.
    if (transientStrength >= 0.015f) {
        CHHapticEventParameter* intensity = [[CHHapticEventParameter alloc]
            initWithParameterID:CHHapticEventParameterIDHapticIntensity value:transientStrength];
        CHHapticEventParameter* eventSharpness = [[CHHapticEventParameter alloc]
            initWithParameterID:CHHapticEventParameterIDHapticSharpness value:sharpness];
        CHHapticEvent* event = [[CHHapticEvent alloc]
            initWithEventType:CHHapticEventTypeHapticTransient
            parameters:@[intensity, eventSharpness]
            relativeTime:0];
        CHHapticPattern* pattern = [[CHHapticPattern alloc]
            initWithEvents:@[event] parameters:@[] error:&error];
        id<CHHapticPatternPlayer> transientPlayer = pattern == nil ? nil :
            [_hapticEngine createPlayerWithPattern:pattern error:&error];
        [transientPlayer startAtTime:CHHapticTimeImmediate error:&error];
        if (error != nil) {
            Log(LOG_W, @"Controller %d: Authored haptic transient failed: %@", _playerIndex, error);
        }
    }
}

-(id) initDeviceEngineContextWithGamepad:(GCController*)gamepad API_AVAILABLE(ios(13.0), tvos(13.0)) {
    NSError *error = nil;
    _hapticEngine = [[CHHapticEngine alloc] initAndReturnError:&error];
    if (error != nil) {
        Log(LOG_W, @"Controller %d: iPhone Haptic engine failed to start: %@", gamepad.playerIndex, error);
        return nil;
    }
    _playerIndex = gamepad.playerIndex;
    
    [_hapticEngine startAndReturnError:&error];
    if (error != nil) {
        Log(LOG_W, @"Controller %d: Haptic engine failed to start: %@", gamepad.playerIndex, error);
        return nil;
    }

    __weak typeof(self) weakSelf = self;
    _hapticEngine.stoppedHandler = ^(CHHapticEngineStoppedReason stoppedReason) {
        HapticContext* me = weakSelf;
        if (me == nil) {
            return;
        }
        
        Log(LOG_W, @"Controller %d: Haptic engine stopped: %p", me->_playerIndex, stoppedReason);
        me->_motorHapticPlayer = nil;
        me->_authoredHapticPlayer = nil;
        me->_hapticEngine = nil;
        me->_motorPlaying = NO;
        me->_authoredPlaying = NO;
    };
    _hapticEngine.resetHandler = ^{
        HapticContext* me = weakSelf;
        if (me == nil) {
            return;
        }
        
        Log(LOG_W, @"Controller %d: Haptic engine reset", me->_playerIndex);
        me->_motorHapticPlayer = nil;
        me->_authoredHapticPlayer = nil;
        me->_motorPlaying = NO;
        me->_authoredPlaying = NO;
        [me->_hapticEngine startAndReturnError:nil];
    };
    
    return self;
}

-(id) initWithGamepad:(GCController*)gamepad locality:(GCHapticsLocality)locality API_AVAILABLE(ios(14.0), tvos(14.0)) {
    bool fallBackToPhoneHaptics = false;
    
    if (gamepad.haptics == nil) {
        Log(LOG_W, @"Controller %d does not support haptics", gamepad.playerIndex);
        fallBackToPhoneHaptics = true;
    }
    else if (![[gamepad.haptics supportedLocalities] containsObject:locality]) {
        Log(LOG_W, @"Controller %d does not support haptic locality: %@", gamepad.playerIndex, locality);
        fallBackToPhoneHaptics = true;
    }

    if (fallBackToPhoneHaptics) {
        Log(LOG_W, @"Controller %d falls back to use iPhone Haptics for locality: %@", gamepad.playerIndex, locality);
        NSError *error = nil;
        _hapticEngine = [[CHHapticEngine alloc] initAndReturnError:&error];
        if (error != nil) {
            Log(LOG_W, @"Controller %d: iPhone Haptic engine failed to start: %@", gamepad.playerIndex, error);
            return nil;
        }
    }
    else {
        _hapticEngine = [gamepad.haptics createEngineWithLocality:locality];
    }
    
    _playerIndex = gamepad.playerIndex;
    
    NSError* error;
    [_hapticEngine startAndReturnError:&error];
    if (error != nil) {
        Log(LOG_W, @"Controller %d: Haptic engine failed to start: %@", gamepad.playerIndex, error);
        return nil;
    }
    
    __weak typeof(self) weakSelf = self;
    _hapticEngine.stoppedHandler = ^(CHHapticEngineStoppedReason stoppedReason) {
        HapticContext* me = weakSelf;
        if (me == nil) {
            return;
        }
        
        Log(LOG_W, @"Controller %d: Haptic engine stopped: %p", me->_playerIndex, stoppedReason);
        me->_motorHapticPlayer = nil;
        me->_authoredHapticPlayer = nil;
        me->_hapticEngine = nil;
        me->_motorPlaying = NO;
        me->_authoredPlaying = NO;
    };
    _hapticEngine.resetHandler = ^{
        HapticContext* me = weakSelf;
        if (me == nil) {
            return;
        }
        
        Log(LOG_W, @"Controller %d: Haptic engine reset", me->_playerIndex);
        me->_motorHapticPlayer = nil;
        me->_authoredHapticPlayer = nil;
        me->_motorPlaying = NO;
        me->_authoredPlaying = NO;
        [me->_hapticEngine startAndReturnError:nil];
    };
    
    return self;
}

+(HapticContext*) createContextForHighFreqMotor:(GCController*)gamepad {
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        return [[HapticContext alloc] initWithGamepad:gamepad locality:GCHapticsLocalityRightHandle];
    }
    else {
        if (@available(iOS 13.0, *)) {
            return [[HapticContext alloc] initDeviceEngineContextWithGamepad:gamepad];
        } else return nil;
    }
}

+(HapticContext*) createContextForLowFreqMotor:(GCController*)gamepad {
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        return [[HapticContext alloc] initWithGamepad:gamepad locality:GCHapticsLocalityLeftHandle];
    }
    else {
        if (@available(iOS 13.0, *)) {
            return [[HapticContext alloc] initDeviceEngineContextWithGamepad:gamepad];
        } else return nil;
    }
}

+(HapticContext*) createContextForLeftTrigger:(GCController*)gamepad {
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        return [[HapticContext alloc] initWithGamepad:gamepad locality:GCHapticsLocalityLeftTrigger];
    }
    else {
        if (@available(iOS 13.0, *)) {
            return [[HapticContext alloc] initDeviceEngineContextWithGamepad:gamepad];
        } else return nil;
    }
}

+(HapticContext*) createContextForRightTrigger:(GCController*)gamepad {
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        return [[HapticContext alloc] initWithGamepad:gamepad locality:GCHapticsLocalityRightTrigger];
    }
    else {
        if (@available(iOS 13.0, *)) {
            return [[HapticContext alloc] initDeviceEngineContextWithGamepad:gamepad];
        } else return nil;
    }
}

@end
