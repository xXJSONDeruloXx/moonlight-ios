//
//  RelativeTouchHandler.m
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "RelativeTouchHandler.h"

#include <Limelight.h>

static const int REFERENCE_WIDTH = 1280;
static const int REFERENCE_HEIGHT = 720;
static const CGFloat PINCH_DETECTION_THRESHOLD = 10.0f;
static const CGFloat PINCH_CONTINUATION_THRESHOLD = 2.0f;
static const NSTimeInterval DOUBLE_TAP_RECOGNITION_INTERVAL = 0.30;
static const CGFloat DOUBLE_TAP_DISTANCE_THRESHOLD_FACTOR = 0.35f;
static const useconds_t SYNTHETIC_CLICK_PRESS_DURATION_US = 50 * 1000;

@implementation RelativeTouchHandler {
    CGPoint touchLocation, originalLocation;
    CGFloat initialTwoFingerDistance;
    CGFloat lastTwoFingerDistance;
    BOOL touchMoved;
    BOOL isDragging;
    BOOL pinchGestureActive;
    NSTimer* dragTimer;
    dispatch_queue_t mouseButtonQueue;
    NSUInteger peakTouchCount;
    NSTimeInterval lastSingleTapTimestamp;
    CGPoint lastSingleTapLocation;
    BOOL lastSingleTapValid;
    
#if TARGET_OS_TV
    UIGestureRecognizer* remotePressRecognizer;
    UIGestureRecognizer* remoteLongPressRecognizer;
#endif
    
    UIView* view;
    BOOL desktopTrackpadMode;
}

- (id)initWithView:(StreamView*)view {
    return [self initWithView:view desktopTrackpadMode:NO];
}

- (id)initWithView:(StreamView*)view desktopTrackpadMode:(BOOL)desktopTrackpadMode {
    self = [self init];
    self->view = view;
    self->desktopTrackpadMode = desktopTrackpadMode;
    self->mouseButtonQueue = dispatch_queue_create("com.moonlight.RelativeTouchHandler.mouseButtons", DISPATCH_QUEUE_SERIAL);
    self->lastSingleTapTimestamp = 0;
    self->lastSingleTapLocation = CGPointZero;
    self->lastSingleTapValid = NO;
    
#if TARGET_OS_TV
    remotePressRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(remoteButtonPressed:)];
    remotePressRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
    
    remoteLongPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(remoteButtonLongPressed:)];
    remoteLongPressRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
    
    [self->view addGestureRecognizer:remotePressRecognizer];
    [self->view addGestureRecognizer:remoteLongPressRecognizer];
#endif
    
    return self;
}

- (BOOL)isConfirmedMove:(CGPoint)currentPoint from:(CGPoint)originalPoint {
    // Movements of greater than 5 pixels are considered confirmed
    return hypotf(originalPoint.x - currentPoint.x, originalPoint.y - currentPoint.y) >= 5;
}

- (void)onDragStart:(NSTimer*)timer {
    if (!touchMoved && !isDragging){
        isDragging = true;
        [self sendMouseButtonAction:BUTTON_ACTION_PRESS button:BUTTON_LEFT];
    }
}

- (void)sendMouseButtonAction:(int)action button:(int)button {
    dispatch_async(mouseButtonQueue, ^{
        LiSendMouseButtonEvent(action, button);
    });
}

- (void)sendSyntheticMouseClick:(int)button {
    dispatch_async(mouseButtonQueue, ^{
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, button);
        usleep(SYNTHETIC_CLICK_PRESS_DURATION_US);
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, button);
    });
}

- (void)clearLastSingleTapState {
    lastSingleTapTimestamp = 0;
    lastSingleTapLocation = CGPointZero;
    lastSingleTapValid = NO;
}

- (void)recordLastSingleTapAtLocation:(CGPoint)location timestamp:(NSTimeInterval)timestamp {
    lastSingleTapTimestamp = timestamp;
    lastSingleTapLocation = location;
    lastSingleTapValid = YES;
}

- (BOOL)isDoubleTapContinuationForTouch:(UITouch*)touch {
    if (!lastSingleTapValid) {
        return NO;
    }

    if (touch.timestamp - lastSingleTapTimestamp > DOUBLE_TAP_RECOGNITION_INTERVAL) {
        return NO;
    }

    CGFloat distanceThreshold = MIN(view.bounds.size.width, view.bounds.size.height) * DOUBLE_TAP_DISTANCE_THRESHOLD_FACTOR;
    CGPoint currentLocation = [touch locationInView:view];
    return hypotf(currentLocation.x - lastSingleTapLocation.x,
                  currentLocation.y - lastSingleTapLocation.y) <= distanceThreshold;
}

- (BOOL)sendRelativeMouseMoveToLocation:(CGPoint)currentLocation {
    if (touchLocation.x == currentLocation.x && touchLocation.y == currentLocation.y) {
        return NO;
    }

    CGFloat viewDeltaX = currentLocation.x - touchLocation.x;
    CGFloat viewDeltaY = currentLocation.y - touchLocation.y;
    int deltaX = viewDeltaX * (REFERENCE_WIDTH / view.bounds.size.width);
    int deltaY = viewDeltaY * (REFERENCE_HEIGHT / view.bounds.size.height);

    if (deltaX == 0 && deltaY == 0) {
        return NO;
    }

    LiSendMouseMoveEvent(deltaX, deltaY);

    if (desktopTrackpadMode && [(StreamView*)view isDesktopViewPanningActive]) {
        [(StreamView*)view updateDesktopViewportForRelativeMotion:CGPointMake(viewDeltaX, viewDeltaY)];
    }

    touchLocation = currentLocation;
    return YES;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    touchMoved = false;
    NSUInteger touchCount = [[event allTouches] count];
    peakTouchCount = touchCount;
    if (touchCount > 1) {
        [dragTimer invalidate];
        dragTimer = nil;
        [self clearLastSingleTapState];
    }
    if (touchCount == 1) {
        UITouch *touch = [[event allTouches] anyObject];
        BOOL doubleTapContinuation = !isDragging && [self isDoubleTapContinuationForTouch:touch];
        originalLocation = touchLocation = [touch locationInView:view];
        initialTwoFingerDistance = 0.0f;
        lastTwoFingerDistance = 0.0f;
        pinchGestureActive = NO;

        [dragTimer invalidate];
        dragTimer = nil;

        if (doubleTapContinuation) {
            isDragging = YES;
            [self sendMouseButtonAction:BUTTON_ACTION_PRESS button:BUTTON_LEFT];
            [self clearLastSingleTapState];
        }
        else if (!isDragging) {
            [self clearLastSingleTapState];
            dragTimer = [NSTimer scheduledTimerWithTimeInterval:0.650
                                                     target:self
                                                   selector:@selector(onDragStart:)
                                                   userInfo:nil
                                                    repeats:NO];
        }
    }
    else if (touchCount == 2) {
        CGPoint firstLocation = [[[[event allTouches] allObjects] objectAtIndex:0] locationInView:view];
        CGPoint secondLocation = [[[[event allTouches] allObjects] objectAtIndex:1] locationInView:view];
        
        originalLocation = touchLocation = CGPointMake((firstLocation.x + secondLocation.x) / 2, (firstLocation.y + secondLocation.y) / 2);
        initialTwoFingerDistance = hypotf(firstLocation.x - secondLocation.x, firstLocation.y - secondLocation.y);
        lastTwoFingerDistance = initialTwoFingerDistance;
        pinchGestureActive = NO;
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([[event allTouches] count] == 1) {
        UITouch *touch = [[event allTouches] anyObject];
        CGPoint currentLocation = [touch locationInView:view];

        if ([self sendRelativeMouseMoveToLocation:currentLocation]) {
            // If we've moved far enough to confirm this wasn't just human/machine error,
            // mark it as such.
            if ([self isConfirmedMove:touchLocation from:originalLocation]) {
                touchMoved = true;
            }
        }
    } else if ([[event allTouches] count] == 2) {
        CGPoint firstLocation = [[[[event allTouches] allObjects] objectAtIndex:0] locationInView:view];
        CGPoint secondLocation = [[[[event allTouches] allObjects] objectAtIndex:1] locationInView:view];
        CGPoint avgLocation = CGPointMake((firstLocation.x + secondLocation.x) / 2, (firstLocation.y + secondLocation.y) / 2);
        BOOL viewPanningActive = desktopTrackpadMode && [(StreamView*)view isDesktopViewPanningActive];
        CGFloat currentTwoFingerDistance = hypotf(firstLocation.x - secondLocation.x, firstLocation.y - secondLocation.y);
        BOOL pinchGestureDetected = desktopTrackpadMode &&
            (fabs(currentTwoFingerDistance - initialTwoFingerDistance) >= PINCH_DETECTION_THRESHOLD ||
             (pinchGestureActive && fabs(currentTwoFingerDistance - lastTwoFingerDistance) >= PINCH_CONTINUATION_THRESHOLD));
        lastTwoFingerDistance = currentTwoFingerDistance;

        if (pinchGestureDetected) {
            pinchGestureActive = YES;
            touchMoved = true;
            touchLocation = avgLocation;
            initialTwoFingerDistance = currentTwoFingerDistance;
            return;
        }

        pinchGestureActive = NO;

        if (viewPanningActive) {
            if ([self sendRelativeMouseMoveToLocation:avgLocation] ||
                [self isConfirmedMove:avgLocation from:originalLocation]) {
                touchMoved = true;
            }
            return;
        }

        if (touchLocation.y != avgLocation.y) {
            LiSendHighResScrollEvent((avgLocation.y - touchLocation.y) * 10);
        }

        // If we've moved far enough to confirm this wasn't just human/machine error,
        // mark it as such.
        if ([self isConfirmedMove:avgLocation from:originalLocation]) {
            touchMoved = true;
        }

        touchLocation = avgLocation;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [dragTimer invalidate];
    dragTimer = nil;
    pinchGestureActive = NO;
    UITouch *endedTouch = [touches anyObject];
    CGPoint endedLocation = [endedTouch locationInView:view];
    NSTimeInterval endedTimestamp = endedTouch.timestamp;
    if ([[event allTouches] count] - [touches count] < 2) {
        initialTwoFingerDistance = 0.0f;
        lastTwoFingerDistance = 0.0f;
    }
    if (isDragging) {
        isDragging = false;
        [self sendMouseButtonAction:BUTTON_ACTION_RELEASE button:BUTTON_LEFT];
        [self clearLastSingleTapState];
    } else if (!touchMoved) {
        if (peakTouchCount == 2) {
            Log(LOG_D, @"Sending right mouse button press");
            [self sendSyntheticMouseClick:BUTTON_RIGHT];
            [self clearLastSingleTapState];
        } else if (peakTouchCount == 1) {
            Log(LOG_D, @"Sending left mouse button press");
            [self sendSyntheticMouseClick:BUTTON_LEFT];
            [self recordLastSingleTapAtLocation:endedLocation timestamp:endedTimestamp];
        } else {
            [self clearLastSingleTapState];
        }
    } else {
        [self clearLastSingleTapState];
    }
    
    // We we're moving from 2+ touches to 1. Synchronize the current position
    // of the active finger so we don't jump unexpectedly on the next touchesMoved
    // callback when finger 1 switches on us.
    if ([[event allTouches] count] - [touches count] == 1) {
        NSMutableSet *activeSet = [[NSMutableSet alloc] initWithCapacity:[[event allTouches] count]];
        [activeSet unionSet:[event allTouches]];
        [activeSet minusSet:touches];
        touchLocation = [[activeSet anyObject] locationInView:view];
        
        // Mark this touch as moved so we don't send a left mouse click if the user
        // right clicks without moving their other finger.
        touchMoved = true;
        [self clearLastSingleTapState];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [dragTimer invalidate];
    dragTimer = nil;
    pinchGestureActive = NO;
    initialTwoFingerDistance = 0.0f;
    lastTwoFingerDistance = 0.0f;
    [self clearLastSingleTapState];
    if (isDragging) {
        isDragging = false;
        [self sendMouseButtonAction:BUTTON_ACTION_RELEASE button:BUTTON_LEFT];
    }
    peakTouchCount = 0;
}

#if TARGET_OS_TV
- (void)remoteButtonPressed:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        Log(LOG_D, @"Sending left mouse button press");
        
        // Mark this as touchMoved to avoid a duplicate press on touch up
        self->touchMoved = true;
        
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        
        // Wait 100 ms to simulate a real button press
        usleep(100 * 1000);
            
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    });
}
- (void)remoteButtonLongPressed:(id)sender {
    Log(LOG_D, @"Holding left mouse button");
    
    isDragging = true;
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
}
#endif

@end
