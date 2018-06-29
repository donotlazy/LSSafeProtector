

//
//  NSObject+Safe.m
//
//  Created by liusong on 2018/4/20.
//

#import "NSObject+Safe.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "NSObject+KVOSafe.h"

@interface LSSafeProxy:NSObject
@property (nonatomic,strong) NSException *exception;
@property (nonatomic,weak) id safe_object;
@end

@implementation LSSafeProxy
+ (BOOL)resolveInstanceMethod:(SEL)sel {
    class_addMethod([self class], sel, [self instanceMethodForSelector:@selector(safe_crashLog)], "v@:");
    return YES;
}
-(void) safe_crashLog
{
     NSString *reason= [NSString stringWithFormat:@"%@ unrecognized selector : %@",NSStringFromClass([self.safe_object class]),NSStringFromSelector(_cmd)];
    NSException *exception=[NSException exceptionWithName:@"NSInvalidArgumentException" reason:reason userInfo:nil];
    LSSafeProtectionCrashLog(exception);
}

@end


@implementation NSObject (Safe)

+(void)openSafeProtector
{
     if ([NSStringFromClass([NSObject class]) isEqualToString:@"NSObject"]) {
         static dispatch_once_t onceToken;
         dispatch_once(&onceToken, ^{
             
             [self safe_exchangeInstanceMethod:[self class] originalSel:@selector(methodSignatureForSelector:) newSel:@selector(safe_methodSignatureForSelector:)];
             
               [self safe_exchangeInstanceMethod:[self class] originalSel:@selector(forwardInvocation:) newSel:@selector(safe_forwardInvocation:)];
             
         });
     }else{
         //只有NSObject 能调用openSafeProtector其他类调用没效果
     }
}
//打开目前所支持的所有安全保护
+(void)openAllSafeProtector
{
    if ([NSStringFromClass([self class]) isEqualToString:@"NSObject"]) {
        [NSObject openSafeProtector];
        [NSArray openSafeProtector];
        [NSMutableArray openSafeProtector];
        [NSDictionary openSafeProtector];
        [NSMutableDictionary openSafeProtector];
        [NSString openSafeProtector];
        [NSMutableString openSafeProtector];
        [NSAttributedString openSafeProtector];
        [NSMutableAttributedString openSafeProtector];
        [NSNotificationCenter openSafeProtector];
        [NSObject openKVOSafeProtector];
    }else{
        //只有NSObject 能调用openAllSafeProtector其他类调用没效果
        [self openSafeProtector];
    }

}
- (NSMethodSignature *)safe_methodSignatureForSelector:(SEL)aSelector
{
    NSMethodSignature *ms = [self safe_methodSignatureForSelector:aSelector];
    if (ms == nil) {
        ms=[LSSafeProxy instanceMethodSignatureForSelector:@selector(safe_crashLog)];
    }
    
    return ms;
}

- (void)safe_forwardInvocation:(NSInvocation *)anInvocation
{
    
    @try {
        [self safe_forwardInvocation:anInvocation];
        
    } @catch (NSException *exception) {
        LSSafeProtectionCrashLog(exception);
        
    } @finally {
        
    }
    
}
#pragma mark - 交换类方法
+ (void)safe_exchangeClassMethod:(Class) dClass
                     originalSel:(SEL)originalSelector
                          newSel:(SEL)newSelector {
    
    Method originalMethod = class_getClassMethod(dClass, originalSelector);
    Method newMethod = class_getClassMethod(dClass, newSelector);
  // Method中包含IMP函数指针，通过替换IMP，使SEL调用不同函数实现
    //方法newMethod的  返回值表示是否添加成功
    BOOL isAdd = class_addMethod(self, originalSelector,
                                 method_getImplementation(newMethod),
                                 method_getTypeEncoding(newMethod));
    // class_addMethod:如果发现方法已经存在，会失败返回，也可以用来做检查用,我们这里是为了避免源方法没有实现的情况;如果方法没有存在,我们则先尝试添加被替换的方法的实现
    if (isAdd) {
        class_replaceMethod(self, newSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        // 添加失败：说明源方法已经有实现，直接将两个方法的实现交换即
        method_exchangeImplementations(originalMethod, newMethod);
    }
}
#pragma mark - 交换对象方法
+ (void)safe_exchangeInstanceMethod : (Class) dClass originalSel:(SEL)originalSelector newSel: (SEL)newSelector {
    Method originalMethod = class_getInstanceMethod(dClass, originalSelector);
    Method newMethod = class_getInstanceMethod(dClass, newSelector);
    // Method中包含IMP函数指针，通过替换IMP，使SEL调用不同函数实现
    //方法newMethod的  返回值表示是否添加成功
    BOOL isAdd = class_addMethod(dClass, originalSelector,
                                 method_getImplementation(newMethod),
                                 method_getTypeEncoding(newMethod));
    // class_addMethod:如果发现方法已经存在，会失败返回，也可以用来做检查用,我们这里是为了避免源方法没有实现的情况;如果方法没有存在,我们则先尝试添加被替换的方法的实现
    if (isAdd) {
        class_replaceMethod(dClass, newSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        // 添加失败：说明源方法已经有实现，直接将两个方法的实现交换即
        method_exchangeImplementations(originalMethod, newMethod);
    }
}


+ (void)safe_logCrashWithException:(NSException *)exception
{
    // 堆栈数据
    NSArray *callStackSymbolsArr = [NSThread callStackSymbols];

    //获取在哪个类的哪个方法中实例化的数组
    NSString *mainMessage = [self safe_getMainCallStackSymbolMessageWithCallStackSymbolString:callStackSymbolsArr[2]];
    
    if (mainMessage == nil) {
        mainMessage = @"崩溃方法定位失败,请您查看函数调用栈来查找crash原因";
    }
    
    NSString *crashName = [NSString stringWithFormat:@"\t\t[Crash Type]: %@",exception.name];
    
    NSString *crashReason = [NSString stringWithFormat:@"\t\t[Crash Reason]: %@",exception.reason];;
    NSString *crashLocation = [NSString stringWithFormat:@"\t\t[Crash Location]: %@",mainMessage];

    NSString *fullMessage = [NSString stringWithFormat:@"\n------------------------------------  Crash START -------------------------------------\n%@\n%@\n%@\n函数堆栈:\n%@\n------------------------------------   Crash END  -----------------------------------------", crashName, crashReason, crashLocation, exception.callStackSymbols];
    LSSafeLog(@"%@", fullMessage);
    
//   UIAlertController *alert= [UIAlertController alertControllerWithTitle:@"检测到崩溃信息" message:fullMessage preferredStyle:(UIAlertControllerStyleAlert)];
//
//    UIAlertAction *action =
//    [UIAlertAction actionWithTitle:@"取消"
//                             style:(UIAlertActionStyleCancel)
//                           handler:^(UIAlertAction *_Nonnull action) {
//                               [alert dismissViewControllerAnimated:YES completion:nil];
//                           }];
//    [alert addAction:action];
//
//    UIViewController *vc= [[[UIApplication sharedApplication] delegate] window].rootViewController;
//    [vc presentViewController:alert animated:YES completion:nil];
    
}

#pragma mark -   获取堆栈主要崩溃精简化的信息<根据正则表达式匹配出来
+ (NSString *)safe_getMainCallStackSymbolMessageWithCallStackSymbolString:(NSString *)callStackSymbolString
{
    
    //正则表达式
    //http://www.jianshu.com/p/b25b05ef170d
    
    //mainCallStackSymbolMsg 的格式为   +[类名 方法名]  或者 -[类名 方法名]
    __block NSString *mainCallStackSymbolMsg = nil;
    
    //匹配出来的格式为 +[类名 方法名]  或者 -[类名 方法名]
    NSString *regularExpStr = @"[-\\+]\\[.+\\]";
    
    NSRegularExpression *regularExp = [[NSRegularExpression alloc] initWithPattern:regularExpStr options:NSRegularExpressionCaseInsensitive error:nil];
    
    [regularExp enumerateMatchesInString:callStackSymbolString options:NSMatchingReportProgress range:NSMakeRange(0, callStackSymbolString.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        if (result) {
            mainCallStackSymbolMsg = [callStackSymbolString substringWithRange:result.range];
            *stop = YES;
        }
    }];
    
    return mainCallStackSymbolMsg;
}


@end