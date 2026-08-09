//
//  MetalView.m
//
//  Created by Andy Grundman.
//  Ported to VoidLink by Acaki.
//  Copyright (c) 2025 Moonlight Stream. All rights reserved.
//
// This is based on the following Apple example
// https://developer.apple.com/documentation/metal/achieving-smooth-frame-rates-with-a-metal-display-link?language=objc
// https://developer.apple.com/wwdc23/10123/

#import "MetalView.h"
#import "MetalConfig.h"

@implementation MetalView {
    // The secondary thread containing the render loop.
    NSThread *_renderThread;
}

#pragma mark - Initialization and Setup.

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (void)initCommon {
    _metalLayer = (CAMetalLayer *)self.layer;
    self.layer.delegate = self;
}

- (void)shutdown {
    if (_renderThread) {
        Log(LOG_I, @"[MetalView] sending renderThread a cancel message");
        [_renderThread cancel];
        Log(LOG_I, @"[MetalView] waiting on renderThread to finish");
        // Bounded wait only: shutdown typically runs on the main thread, and the render
        // thread may be blocked in a dispatch_sync onto the main queue (layer colorspace
        // changes). Spinning here forever would deadlock; if we time out, the thread
        // exits on its own once the main queue is serviced again (it retains the view
        // via its block, so this is safe).
        CFTimeInterval deadline = CACurrentMediaTime() + 1.0;
        while (!_renderThread.isFinished && CACurrentMediaTime() < deadline) {
            usleep(100);
        }
        if (_renderThread.isFinished) {
            Log(LOG_I, @"[MetalView] renderThread has finished");
        } else {
            Log(LOG_W, @"[MetalView] renderThread still busy after 1s, letting it exit asynchronously");
        }
        _renderThread = nil;
    }
}

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (void)didMoveToWindow {
    [self movedToWindow];
}

- (void)movedToWindow {
    if (!self.window) {
        Log(LOG_I, @"[MetalView] movedToWindow(nil): shutting down...");
        [self shutdown];
        return;
    }

    // Never run two render loops at once (the view can move between windows,
    // e.g. external display or re-parenting)
    if (_renderThread) {
        Log(LOG_W, @"[MetalView] movedToWindow with a live renderThread, restarting it");
        [self shutdown];
    }

    // Render on a new thread
    _renderThread = [[NSThread alloc] initWithBlock:^{
        while (![NSThread currentThread].isCancelled) {
            @autoreleasepool {
                [self.delegate waitToRenderTo:self.metalLayer];
                [self.delegate renderTo:self.metalLayer];
            }
        }
        Log(LOG_I, @"[MetalView] renderThread is exiting");
    }];
    _renderThread.name = @"MetalVideoRenderer";
    _renderThread.qualityOfService = NSQualityOfServiceUserInteractive;
    [_renderThread start];
    Log(LOG_I, @"[MetalView] started renderThread %@", _renderThread);

    // Perform any actions that need to know the size and scale of the drawable. When UIKit calls
    // didMoveToWindow after the view initialization, this is the first opportunity to notify
    // components of the drawable's size.
#if AUTOMATICALLY_RESIZE
    [self resizeDrawable:self.window.screen.nativeScale];
#else
    // Notify the delegate of the default drawable size when the system can calculate it.
    CGSize defaultDrawableSize = self.bounds.size;
    defaultDrawableSize.width *= self.layer.contentsScale;
    defaultDrawableSize.height *= self.layer.contentsScale;
    [self.delegate drawableResize:defaultDrawableSize];
#endif
}

#pragma mark - Resizing

#if AUTOMATICALLY_RESIZE

// Override all methods that indicate the view's size has changed.

- (void)setContentScaleFactor:(CGFloat)contentScaleFactor {
    [super setContentScaleFactor:contentScaleFactor];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)resizeDrawable:(CGFloat)scaleFactor {
    CGSize newSize = self.bounds.size;
    newSize.width *= scaleFactor;
    newSize.height *= scaleFactor;

    if (newSize.width <= 0 || newSize.width <= 0) {
        return;
    }

    // The system calls all AppKit and UIKit calls that notify of a resize on the main thread. Use
    // a synchronized block to ensure that resize notifications on the delegate are atomic.
    @synchronized(_metalLayer) {
        if (newSize.width == _metalLayer.drawableSize.width && newSize.height == _metalLayer.drawableSize.height) {
            return;
        }

        Log(LOG_I, @"[MetalView] resizeDrawable: %.2f x %.2f", newSize.width, newSize.height);

        _metalLayer.drawableSize = newSize;

        [_delegate drawableResize:newSize];
    }
}
#endif  // END AUTOMATICALLY_RESIZE

@end
