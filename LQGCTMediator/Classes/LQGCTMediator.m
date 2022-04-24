//
//  LQGCTMediator.m
//  LQGCTMediator
//
//  Created by 罗建
//  Copyright (c) 2021 罗建. All rights reserved.
//

#import "LQGCTMediator.h"

#import <objc/runtime.h>

NSString * const kCTMediatorParamsKeySwiftTargetModuleName = @"kCTMediatorParamsKeySwiftTargetModuleName";

@interface LQGCTMediator ()

@property (nonatomic, strong) NSMutableDictionary *cachedTarget;

@end

@implementation LQGCTMediator


#pragma mark - 单例

+ (instancetype)sharedInstance {
    static LQGCTMediator *mediator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mediator = [[LQGCTMediator alloc] init];
    });
    return mediator;
}


#pragma mark - Life Cycle

- (instancetype)init {
    if (self = [super init]) {
        // 直接初始化cachedTarget，避免多线程重复初始化
        self.cachedTarget = [[NSMutableDictionary alloc] init];
    }
    return self;
}


#pragma mark - Other Method

- (id)performActionWithUrl:(NSURL *)url
                completion:(void (^)(NSDictionary *))completion {
    if (!url ||
        ![url isKindOfClass:[NSURL class]]) {
        return nil;
    }
    
    // 这里这么写主要是出于安全考虑，防止黑客通过远程方式调用本地模块。这里的做法足以应对绝大多数场景，如果要求更加严苛，也可以做更加复杂的安全逻辑。
    NSString *actionName = [url.path stringByReplacingOccurrencesOfString:@"/" withString:@""];
    if ([actionName hasPrefix:@"native"]) {
        return @(NO);
    }
    
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    NSURLComponents *urlComponents = [[NSURLComponents alloc] initWithString:url.absoluteString];
    [urlComponents.queryItems enumerateObjectsUsingBlock:^(NSURLQueryItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.name && obj.value) {
            [params setObject:obj.value forKey:obj.name];
        }
    }];
    
    // 这个demo针对URL的路由处理非常简单，就只是取对应的target名字和method名字，但这已经足以应对绝大部份需求。如果需要拓展，可以在这个方法调用之前加入完整的路由逻辑
    id result = [self performTarget:url.host action:actionName params:params shouldCacheTarget:NO];
    if (completion) {
        completion(result ? @{
            @"result": result
        } : nil);
    }
    return result;
}

- (id)performTarget:(NSString *)targetName
             action:(NSString *)actionName
             params:(NSDictionary *)params
  shouldCacheTarget:(BOOL)shouldCacheTarget {
    if (!targetName.length || !actionName.length) {
        return nil;
    }
    
    NSString *swiftModuleName = params[kCTMediatorParamsKeySwiftTargetModuleName];
    
    // generate target
    NSString *targetClassString = nil;
    if (swiftModuleName.length) {
        targetClassString = [NSString stringWithFormat:@"%@.Target_%@", swiftModuleName, targetName];
    } else {
        targetClassString = [NSString stringWithFormat:@"Target_%@", targetName];
    }
    
    NSObject *target = [self safeFetchCachedTarget:targetClassString];
    if (!target) {
        target = [[NSClassFromString(targetClassString) alloc] init];
    }
    
    // generate action
    NSString *actionString = [NSString stringWithFormat:@"Action_%@:", actionName];
    SEL action = NSSelectorFromString(actionString);
    
    if (target) {
        if (shouldCacheTarget) {
            [self safeSetCachedTarget:target key:targetClassString];
        }
        
        if ([target respondsToSelector:action]) {
            return [self safePerformTarget:target action:action params:params];
        }
        
        // 这里是处理无响应请求的地方，如果没有可以响应的action，则尝试调用对应target的notFound方法统一处理
        SEL action = NSSelectorFromString(@"notFound:");
        if ([target respondsToSelector:action]) {
            return [self safePerformTarget:target action:action params:params];
        }
    }
    
    // 这里是处理无响应请求的地方，如果没有可以响应的target，就直接return了。
    // 实际开发过程中是可以事先给一个固定的target专门用于在这个时候顶上，然后处理这种请求的
    [self NoTargetActionResponseWithTargetString:targetClassString selectorString:actionString originParams:params];
    return nil;
}

- (void)NoTargetActionResponseWithTargetString:(NSString *)targetString
                                selectorString:(NSString *)selectorString
                                  originParams:(NSDictionary *)originParams {
    NSObject *target = [[NSClassFromString(@"Target_NoTargetAction") alloc] init];
    SEL action = NSSelectorFromString(@"Action_response:");
    
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    params[@"targetString"] = targetString;
    params[@"selectorString"] = selectorString;
    params[@"originParams"] = originParams;
    
    [self safePerformTarget:target action:action params:params];
}

- (id)safePerformTarget:(NSObject *)target
                 action:(SEL)action
                 params:(NSDictionary *)params {
    NSMethodSignature *methodSig = [target methodSignatureForSelector:action];
    if (methodSig == nil) {
        return nil;
    }
    
    const char *retType = [methodSig methodReturnType];
    
    if (strcmp(retType, @encode(void)) == 0) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
        [invocation setArgument:&params atIndex:2];
        [invocation setSelector:action];
        [invocation setTarget:target];
        [invocation invoke];
        return nil;
    }
    
    if (strcmp(retType, @encode(NSInteger)) == 0) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
        [invocation setArgument:&params atIndex:2];
        [invocation setSelector:action];
        [invocation setTarget:target];
        [invocation invoke];
        NSInteger result = 0;
        [invocation getReturnValue:&result];
        return @(result);
    }
    
    if (strcmp(retType, @encode(BOOL)) == 0) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
        [invocation setArgument:&params atIndex:2];
        [invocation setSelector:action];
        [invocation setTarget:target];
        [invocation invoke];
        BOOL result = 0;
        [invocation getReturnValue:&result];
        return @(result);
    }
    
    if (strcmp(retType, @encode(CGFloat)) == 0) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
        [invocation setArgument:&params atIndex:2];
        [invocation setSelector:action];
        [invocation setTarget:target];
        [invocation invoke];
        CGFloat result = 0;
        [invocation getReturnValue:&result];
        return @(result);
    }
    
    if (strcmp(retType, @encode(NSUInteger)) == 0) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
        [invocation setArgument:&params atIndex:2];
        [invocation setSelector:action];
        [invocation setTarget:target];
        [invocation invoke];
        NSUInteger result = 0;
        [invocation getReturnValue:&result];
        return @(result);
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [target performSelector:action withObject:params];
#pragma clang diagnostic pop
}

- (void)releaseCachedTargetWithFullTargetName:(NSString *)fullTargetName {
    if (!fullTargetName.length) {
        return;
    }
    [self safeSetCachedTarget:nil key:fullTargetName];
}


#pragma mark - Getter/Setter

- (NSObject *)safeFetchCachedTarget:(NSString *)key {
    @synchronized (self) {
        return self.cachedTarget[key];
    }
}

- (void)safeSetCachedTarget:(NSObject *)target key:(NSString *)key {
    @synchronized (self) {
        self.cachedTarget[key] = target;
    }
}

@end

LQGCTMediator * CT(void) {
    return [LQGCTMediator sharedInstance];
}
