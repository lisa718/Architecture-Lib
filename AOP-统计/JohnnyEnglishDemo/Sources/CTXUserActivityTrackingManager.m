//
//  CTXUserActivityTrackingManager.m
//  JohnnyEnglish
//
//  Created by Alberto De Bortoli on 29/01/2014.
//  Copyright (c) 2014 EF CTX. All rights reserved.
//  Licensed under the MIT license.
//

#import "CTXUserActivityTrackingManager.h"

#import "CTXUserActivityTrackerProtocol.h"

#import "CTXUserActivityEvent.h"
#import "CTXUserActivityTiming.h"
#import "CTXUserActivityScreenHit.h"

#import "Aspects.h"

static NSString *const CTXTrackTimerStartDate           = @"startTimer";
static NSString *const CTXTrackTimerStartMethodInfo     = @"startMethodInfo";

@interface CTXMethodCallInfo()
@property (strong, nonatomic) id<AspectInfo> info;
@end

@implementation CTXMethodCallInfo

- (instancetype)initWithAspectInfo:(id<AspectInfo>)info;
{
    if (self = [super init]) {
        _info = info;
        _instance = [info instance];
        _originalInvocation = [info originalInvocation];
    }
    return self;
}

- (NSArray *)arguments
{
    return [self.info arguments];
}

@end


@interface CTXUserActivityTrackingManager ()

@property (nonatomic, strong) NSMutableArray *trackers;
@property (nonatomic, strong) NSMutableDictionary *timerTrackers;

@end

@implementation CTXUserActivityTrackingManager
{
    dispatch_queue_t _workingQueue;
}

- (instancetype)init
{
    if (self = [super init]) {
        _trackers = [NSMutableArray array];
        _timerTrackers = [NSMutableDictionary dictionary];
        _workingQueue = dispatch_queue_create("com.ef.ctx.user-activity-tracking-manager", DISPATCH_QUEUE_CONCURRENT);
    }
    
    return self;
}

- (void)registerTracker:(id<CTXUserActivityTrackerProtocol>)tracker
{
    NSParameterAssert(tracker);

    if ([tracker conformsToProtocol:@protocol(CTXUserActivityTrackerProtocol)]) {
        [self.trackers addObject:tracker];
    }
}

- (void)registerUserIdFromClass:(Class)clazz selector:(SEL)selektor userIdCallback:(NSString * (^)(CTXMethodCallInfo *callInfo))userIdCallback error:(NSError **)error
{
    NSParameterAssert(clazz);
    NSParameterAssert(selektor);
    NSParameterAssert(userIdCallback);
    
    __weak typeof(self) weakSelf = self;

    [clazz aspect_hookSelector:selektor
                   withOptions:AspectPositionAfter
                    usingBlock:^(id<AspectInfo> info) {
                        NSString *userId = userIdCallback([[CTXMethodCallInfo alloc] initWithAspectInfo:info]);
                        dispatch_async(_workingQueue, ^{
                            for (id<CTXUserActivityTrackerProtocol> tracker in weakSelf.trackers) {
                                [tracker trackUserId:userId];
                            }
                        });
                    }
                         error:error];
}

- (void)registerScreenTrackerFromClass:(Class)clazz screenName:(NSString *)screenName error:(NSError **)error
{
    NSParameterAssert(clazz);
    NSParameterAssert(screenName);

    [self registerScreenTrackerFromClass:clazz screenCallback:^CTXUserActivityScreenHit *(CTXMethodCallInfo *callInfo) {
        CTXUserActivityScreenHit *screenHit = [[CTXUserActivityScreenHit alloc] init];
        screenHit.screenName = screenName;
        return screenHit;
    } error:error];
}

- (void)registerScreenTrackerFromClass:(Class)clazz screenCallback:(CTXUserActivityScreenHit * (^)(CTXMethodCallInfo *callInfo))screenCallback error:(NSError **)error
{
    NSParameterAssert(clazz);
    NSParameterAssert(screenCallback);

    __weak typeof(self) weakSelf = self;
    
    [clazz aspect_hookSelector:@selector(viewDidAppear:)
                   withOptions:AspectPositionAfter
                    usingBlock:^(id<AspectInfo> info) {
                        CTXUserActivityScreenHit *screenHit = screenCallback([[CTXMethodCallInfo alloc] initWithAspectInfo:info]);
                        
                        if (!screenHit) {
                            return;
                        }
                        dispatch_async(_workingQueue, ^{
                            for (id<CTXUserActivityTrackerProtocol> tracker in weakSelf.trackers) {
                                [tracker trackScreenHit:screenHit];
                            }
                        });
                    }
                         error:error];
}

- (void)registerEventTrackerFromClass:(Class)clazz selector:(SEL)selektor event:(CTXUserActivityEvent *)event error:(NSError **)error
{
    NSParameterAssert(clazz);
    NSParameterAssert(selektor);
    NSParameterAssert(event);

    __weak typeof(self) weakSelf = self;
    
    [clazz aspect_hookSelector:selektor
                   withOptions:AspectPositionBefore
                    usingBlock:^(id<AspectInfo> info) {
                        if (!event) {
                            return;
                        }
                        dispatch_async(_workingQueue, ^{
                            for (id<CTXUserActivityTrackerProtocol> tracker in weakSelf.trackers) {
                                [tracker trackEvent:event];
                            }
                        });
                    }
                         error:error];
}

- (void)registerEventTrackerFromClass:(Class)clazz selector:(SEL)selektor eventCallback:(CTXUserActivityEvent * (^)(CTXMethodCallInfo *callInfo))eventCallback error:(NSError **)error
{
    NSParameterAssert(clazz);
    NSParameterAssert(selektor);
    NSParameterAssert(eventCallback);
    
    __weak typeof(self) weakSelf = self;

    [clazz aspect_hookSelector:selektor
                   withOptions:AspectPositionBefore
                    usingBlock:^(id<AspectInfo> info) {
                        CTXUserActivityEvent *event = eventCallback([[CTXMethodCallInfo alloc] initWithAspectInfo:info]);
                        
                        if (!event) {
                            return;
                        }
                        dispatch_async(_workingQueue, ^{
                            for (id<CTXUserActivityTrackerProtocol> tracker in weakSelf.trackers) {
                                [tracker trackEvent:event];
                            }
                        });
                    }
                         error:error];
}

- (void)registerStartTimerTrackerFromClass:(Class)clazz selector:(SEL)selektor timerUUIDCallback:(NSString * (^)(CTXMethodCallInfo *callInfo))uuidCallback error:(NSError **)error
{
    NSParameterAssert(clazz);
    NSParameterAssert(selektor);
    NSParameterAssert(uuidCallback);

    __weak typeof(self) weakSelf = self;
    
    [clazz aspect_hookSelector:selektor
                   withOptions:AspectPositionBefore
                    usingBlock:^(id<AspectInfo> info) {
                        CTXMethodCallInfo *invocation = [[CTXMethodCallInfo alloc] initWithAspectInfo:info];
                        NSString *uuid = uuidCallback(invocation);
                        
                        dispatch_async(_workingQueue, ^{
                            weakSelf.timerTrackers[uuid] = @{CTXTrackTimerStartDate:[NSDate new], CTXTrackTimerStartMethodInfo:invocation} ;
                        });
                    }
                         error:error];
}

- (void)registerStopTimerTrackerFromClass:(Class)clazz
                                 selector:(SEL)selektor
                        timerUUIDCallback:(NSString * (^)(CTXMethodCallInfo *callInfo))uuidCallback
                            eventCallback:(CTXUserActivityTiming * (^)(CTXMethodCallInfo *startMethodCallInfo, CTXMethodCallInfo *stopMethodCallInfo, NSTimeInterval duration))eventCallback
                                    error:(NSError **)error
{
    NSParameterAssert(clazz);
    NSParameterAssert(selektor);
    NSParameterAssert(uuidCallback);
    NSParameterAssert(eventCallback);
    
    __weak typeof(self) weakSelf = self;

    [clazz aspect_hookSelector:selektor
                   withOptions:AspectPositionBefore
                    usingBlock:^(id<AspectInfo> info) {
                        NSString *uuid = uuidCallback([[CTXMethodCallInfo alloc] initWithAspectInfo:info]);
                        NSDictionary *startInfo = weakSelf.timerTrackers[uuid];
                        [self.timerTrackers removeObjectForKey:uuid];
                        
                        if (!startInfo) {
                            NSLog(@"WARNING: [%@] Stop timer without a proper start with uuid %@", NSStringFromSelector(_cmd), uuid);
                            return;
                        }
                        
                        NSTimeInterval duration = [[NSDate new] timeIntervalSinceDate:startInfo[CTXTrackTimerStartDate]];
                        CTXUserActivityTiming *timing = eventCallback(startInfo[CTXTrackTimerStartMethodInfo], [[CTXMethodCallInfo alloc] initWithAspectInfo:info], duration);
                        
                        if (!timing) {
                            return;
                        }
                        dispatch_async(_workingQueue, ^{
                            
                            for (id<CTXUserActivityTrackerProtocol> tracker in weakSelf.trackers) {
                                [tracker trackTiming:timing];
                            }
                        });
                    }
                         error:error];
}

- (void)registerTimeTrackerFromClass:(Class)clazz
                       startSelector:(SEL)startSelektor
                        stopSelector:(SEL)stopSelektor
                       eventCallback:(CTXUserActivityTiming * (^)(CTXMethodCallInfo *startMethodCallInfo, CTXMethodCallInfo *stopMethodCallInfo, NSTimeInterval duration))eventCallback
                               error:(NSError **)error
{
    NSParameterAssert(clazz);
    NSParameterAssert(startSelektor);
    NSParameterAssert(stopSelektor);
    NSParameterAssert(eventCallback);

    NSString *(^timerCallback)(CTXMethodCallInfo *callInfo) = ^NSString *(CTXMethodCallInfo *callInfo){
        return [NSString stringWithFormat:@"%lu|%@|%@", (unsigned long)[[callInfo instance] hash], NSStringFromSelector(startSelektor), NSStringFromSelector(stopSelektor)];
    };
    
    [self registerStartTimerTrackerFromClass:clazz
                                    selector:startSelektor
                           timerUUIDCallback:timerCallback
                                       error:error];
    
    if ((error != NULL) && *error) {
        return;
    }
    [self registerStopTimerTrackerFromClass:clazz
                                   selector:stopSelektor
                          timerUUIDCallback:timerCallback
                              eventCallback:eventCallback
                                      error:error];
}

@end
