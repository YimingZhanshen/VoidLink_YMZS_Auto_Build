//
//  GameSirG8MFiRumble.m
//  VoidLink
//

#import "GameSirG8MFiRumble.h"

@import ExternalAccessory;
@import GameController;
@import UIKit;

static NSString *const GameSirG8MFiProtocol = @"com.xiaoji.M2boot";
static NSString *const GameSirManufacturer = @"GameSir";
static NSString *const GameSirG8MFiModel = @"G8+ MFi";

@interface GameSirG8MFiRumble () <NSStreamDelegate>
@end

@implementation GameSirG8MFiRumble {
    EASession *_session;
    NSData *_inFlightPacket;
    NSUInteger _inFlightOffset;
    NSData *_queuedPacket;
    NSData *_lastSentPacket;
    BOOL _appActive;
    BOOL _invalidated;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _appActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationWillResignActive:)
                                                   name:UIApplicationWillResignActiveNotification
                                                 object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationDidBecomeActive:)
                                                   name:UIApplicationDidBecomeActiveNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (NSThread.isMainThread) {
        [self writeStopPacketBestEffort];
    }
    [self closeSession];
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    _appActive = NO;
    [self stopAndCloseOnMainThread];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    _appActive = YES;
}

- (BOOL)isTargetController:(GCController *)controller {
    NSString *vendorName = controller.vendorName;
    if (vendorName.length == 0) {
        return NO;
    }

    NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    return [vendorName rangeOfString:GameSirManufacturer options:options].location != NSNotFound &&
        [vendorName rangeOfString:@"G8+" options:options].location != NSNotFound && [vendorName rangeOfString:@"MFi" options:options].location != NSNotFound;
}

- (EAAccessory *)connectedAccessory {
    for (EAAccessory *accessory in EAAccessoryManager.sharedAccessoryManager.connectedAccessories) {
        if (!accessory.connected || ![accessory.protocolStrings containsObject:GameSirG8MFiProtocol]) {
            continue;
        }
        if (accessory.manufacturer.length == 0 || accessory.modelNumber.length == 0 ||
            [accessory.manufacturer caseInsensitiveCompare:GameSirManufacturer] != NSOrderedSame ||
            [accessory.modelNumber caseInsensitiveCompare:GameSirG8MFiModel] != NSOrderedSame) {
            continue;
        }
        return accessory;
    }
    return nil;
}

- (BOOL)canHandleController:(GCController *)controller {
    return [self isTargetController:controller] && [self connectedAccessory] != nil;
}

+ (uint8_t)convertMotorAmplitude:(uint16_t)amplitude {
    return (uint8_t)(((uint32_t)amplitude * 255u + 32767u) / 65535u);
}

- (NSData *)packetForLowFrequencyMotor:(uint16_t)lowFrequencyMotor highFrequencyMotor:(uint16_t)highFrequencyMotor {
    const uint8_t packet[] = {
        0x04,
        [GameSirG8MFiRumble convertMotorAmplitude:lowFrequencyMotor],
        0x01,
        [GameSirG8MFiRumble convertMotorAmplitude:highFrequencyMotor],
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
    };
    return [NSData dataWithBytes:packet length:sizeof(packet)];
}

- (BOOL)openSessionIfNeeded {
    if (_session != nil) {
        return YES;
    }

    EAAccessory *accessory = [self connectedAccessory];
    if (accessory == nil) {
        return NO;
    }

    EASession *session = [[EASession alloc] initWithAccessory:accessory forProtocol:GameSirG8MFiProtocol];
    if (session == nil || session.inputStream == nil || session.outputStream == nil) {
        return NO;
    }

    _session = session;
    session.inputStream.delegate = self;
    session.outputStream.delegate = self;
    [session.inputStream scheduleInRunLoop:NSRunLoop.mainRunLoop forMode:NSDefaultRunLoopMode];
    [session.outputStream scheduleInRunLoop:NSRunLoop.mainRunLoop forMode:NSDefaultRunLoopMode];
    [session.inputStream open];
    [session.outputStream open];
    return YES;
}

- (void)setLowFrequencyMotor:(uint16_t)lowFrequencyMotor highFrequencyMotor:(uint16_t)highFrequencyMotor {
    @synchronized(self) {
        if (_invalidated) {
            return;
        }
    }

    NSData *packet = [self packetForLowFrequencyMotor:lowFrequencyMotor highFrequencyMotor:highFrequencyMotor];
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized(self) {
            if (self->_invalidated) {
                return;
            }
        }
        if (!self->_appActive) {
            return;
        }

        BOOL duplicateQueuedPacket = [self->_queuedPacket isEqualToData:packet];
        BOOL duplicateInFlightPacket = self->_queuedPacket == nil && [self->_inFlightPacket isEqualToData:packet];
        BOOL duplicateSentPacket = self->_queuedPacket == nil && self->_inFlightPacket == nil && [self->_lastSentPacket isEqualToData:packet];
        if (!duplicateQueuedPacket && !duplicateInFlightPacket && !duplicateSentPacket) {
            self->_queuedPacket = packet;
        }

        if ([self openSessionIfNeeded]) {
            [self flushOutput];
        }
    });
}

- (void)flushOutput {
    NSOutputStream *outputStream = _session.outputStream;
    if (outputStream.streamStatus != NSStreamStatusOpen || !outputStream.hasSpaceAvailable) {
        return;
    }

    while (outputStream.hasSpaceAvailable) {
        if (_inFlightPacket == nil) {
            if (_queuedPacket == nil) {
                return;
            }
            _inFlightPacket = _queuedPacket;
            _queuedPacket = nil;
            _inFlightOffset = 0;
        }

        const uint8_t *bytes = _inFlightPacket.bytes;
        NSUInteger remainingLength = _inFlightPacket.length - _inFlightOffset;
        NSInteger written = [outputStream write:&bytes[_inFlightOffset] maxLength:remainingLength];
        if (written <= 0) {
            return;
        }

        _inFlightOffset += (NSUInteger)written;
        if (_inFlightOffset == _inFlightPacket.length) {
            _lastSentPacket = _inFlightPacket;
            _inFlightPacket = nil;
            _inFlightOffset = 0;
        }
    }
}

- (void)writeStopPacketBestEffort {
    NSOutputStream *outputStream = _session.outputStream;
    if (outputStream.streamStatus != NSStreamStatusOpen || !outputStream.hasSpaceAvailable) {
        return;
    }

    _queuedPacket = nil;
    [self flushOutput];
    if (_inFlightPacket != nil) {
        return;
    }

    NSData *stopPacket = [self packetForLowFrequencyMotor:0 highFrequencyMotor:0];
    NSUInteger offset = 0;
    while (offset < stopPacket.length && outputStream.hasSpaceAvailable) {
        const uint8_t *bytes = stopPacket.bytes;
        NSInteger written = [outputStream write:&bytes[offset] maxLength:stopPacket.length - offset];
        if (written <= 0) {
            break;
        }
        offset += (NSUInteger)written;
    }
    if (offset == stopPacket.length) {
        _lastSentPacket = stopPacket;
    }
}

- (void)closeSession {
    if (_session != nil) {
        [_session.inputStream close];
        [_session.outputStream close];
        [_session.inputStream removeFromRunLoop:NSRunLoop.mainRunLoop forMode:NSDefaultRunLoopMode];
        [_session.outputStream removeFromRunLoop:NSRunLoop.mainRunLoop forMode:NSDefaultRunLoopMode];
        _session.inputStream.delegate = nil;
        _session.outputStream.delegate = nil;
    }

    _session = nil;
    _inFlightPacket = nil;
    _inFlightOffset = 0;
    _queuedPacket = nil;
    _lastSentPacket = nil;
}

- (void)stopAndCloseOnMainThread {
    [self writeStopPacketBestEffort];
    [self closeSession];
}

- (void)stopAndClose {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopAndCloseOnMainThread];
    });
}

- (void)invalidate {
    @synchronized(self) {
        _invalidated = YES;
    }
    [self stopAndClose];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    if (stream != _session.inputStream && stream != _session.outputStream) {
        return;
    }

    switch (eventCode) {
        case NSStreamEventHasBytesAvailable: {
            uint8_t buffer[64];
            while (_session.inputStream.hasBytesAvailable) {
                if ([_session.inputStream read:buffer maxLength:sizeof(buffer)] <= 0) {
                    break;
                }
            }
            break;
        }
        case NSStreamEventOpenCompleted:
        case NSStreamEventHasSpaceAvailable:
            if (stream == _session.outputStream) {
                [self flushOutput];
            }
            break;
        case NSStreamEventErrorOccurred:
        case NSStreamEventEndEncountered:
            [self writeStopPacketBestEffort];
            [self closeSession];
            break;
        case NSStreamEventNone:
            break;
    }
}

@end
