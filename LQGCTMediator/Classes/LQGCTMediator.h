//
//  LQGCTMediator.h
//  LQGCTMediator
//
//  Created by 罗建
//  Copyright (c) 2021 罗建. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString * const kCTMediatorParamsKeySwiftTargetModuleName;

/// 中间层
@interface LQGCTMediator : NSObject

/// 单例
+ (instancetype)sharedInstance;

/// 远程App调用入口
/// @param url 链接(格式 scheme://[target]/[action]?[params] 例子 aaa://targetA/actionB?id=1234)
/// @param completion 回调
- (id)performActionWithUrl:(NSURL *)url
                completion:(void(^)(NSDictionary *info))completion;

/// 本地组件调用入口
/// @param targetName 对象名称
/// @param actionName 方法名称
/// @param params 参数
/// @param shouldCacheTarget 是否缓存
- (id)performTarget:(NSString *)targetName
             action:(NSString *)actionName
             params:(NSDictionary *)params
  shouldCacheTarget:(BOOL)shouldCacheTarget;

/// 释放缓存的对象
/// @param fullTargetName 缓存的对象名称。在oc环境下是Target_XXXX，要带上Target_前缀。在swift环境下是XXXModule.Target_YYY，不光要带上Target_前缀，还要带上模块名。
- (void)releaseCachedTargetWithFullTargetName:(NSString *)fullTargetName;

@end

/// 简化调用单例的函数
LQGCTMediator * CT(void);
