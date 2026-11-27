#include <stdint.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "bt_kit.h"

#if !__has_feature(objc_arc)
#error "This file must be compiled with ARC enabled"
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct {
  int64_t version;
  void* (*newWaiter)(void);
  void (*awaitWaiter)(void*);
  void* (*currentIsolate)(void);
  void (*enterIsolate)(void*);
  void (*exitIsolate)(void);
  int64_t (*getMainPortId)(void);
  bool (*getCurrentThreadOwnsIsolate)(int64_t);
  void (*invokeListenerPortBlock)(int64_t port, void*);
  void (*invokeBlockingPortBlock)(int64_t port, void*, void*);
} DOBJC_Context;

id objc_retainBlock(id);

#define BLOCKING_BLOCK_IMPL(ctx, TYPE, SIG, INVOKE_DIRECT, INVOKE_LISTENER)    \
  assert(ctx->version >= 1);                                                   \
  void* targetIsolate = ctx->currentIsolate();                                 \
  int64_t targetPort = ctx->getMainPortId == NULL ? 0 : ctx->getMainPortId();  \
  __block __weak TYPE weakSelfBlock = nil;                                     \
  TYPE strongSelfBlock = [SIG {                                                \
    void* currentIsolate = ctx->currentIsolate();                              \
    bool mayEnterIsolate =                                                     \
        currentIsolate == NULL &&                                              \
        ctx->getCurrentThreadOwnsIsolate != NULL &&                            \
        ctx->getCurrentThreadOwnsIsolate(targetPort);                          \
    if (currentIsolate == targetIsolate || mayEnterIsolate) {                  \
      if (mayEnterIsolate) {                                                   \
        ctx->enterIsolate(targetIsolate);                                      \
      }                                                                        \
      INVOKE_DIRECT;                                                           \
      if (mayEnterIsolate) {                                                   \
        ctx->exitIsolate();                                                    \
      }                                                                        \
    } else {                                                                   \
      void* waiter = ctx->newWaiter();                                         \
      TYPE selfRetain = [weakSelfBlock copy];                                  \
      INVOKE_LISTENER;                                                         \
      ctx->awaitWaiter(waiter);                                                \
      (void)selfRetain;                                                        \
    }                                                                          \
  } copy];                                                                     \
  weakSelfBlock = strongSelfBlock;                                             \
  return strongSelfBlock;


__attribute__((visibility("default"))) __attribute__((used))
Protocol* _1kze1be_CBCentralManagerDelegate(void) { return @protocol(CBCentralManagerDelegate); }

__attribute__((visibility("default"))) __attribute__((used))
Protocol* _1kze1be_CBPeripheralDelegate(void) { return @protocol(CBPeripheralDelegate); }

__attribute__((visibility("default"))) __attribute__((used))
Protocol* _1kze1be_CBPeripheralManagerDelegate(void) { return @protocol(CBPeripheralManagerDelegate); }

__attribute__((visibility("default"))) __attribute__((used))
Protocol* _1kze1be_EAAccessoryDelegate(void) { return @protocol(EAAccessoryDelegate); }

__attribute__((visibility("default")))
@interface _1kze1be_BlockArgs_xtuoz7 : NSObject
@property (copy) id block;
@property (strong) id arg0;
@end
@implementation _1kze1be_BlockArgs_xtuoz7
@end

typedef void  (^_ListenerTrampoline)(id arg0);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline _1kze1be_wrapListenerBlock_xtuoz7(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline weakSelfBlock = nil;
  _ListenerTrampoline strongSelfBlock = [^void(id arg0) {
    @autoreleasepool {
      _1kze1be_BlockArgs_xtuoz7* args = [[_1kze1be_BlockArgs_xtuoz7 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline)(void * waiter, id arg0);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline _1kze1be_wrapBlockingBlock_xtuoz7(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline, ^void(id arg0), {
    @autoreleasepool {
      _1kze1be_BlockArgs_xtuoz7* args = [[_1kze1be_BlockArgs_xtuoz7 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _1kze1be_BlockArgs_xtuoz7* args = [[_1kze1be_BlockArgs_xtuoz7 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _1kze1be_BlockArgs_pfv6jd : NSObject
@property (copy) id block;
@property (strong) id arg0;
@property (strong) id arg1;
@end
@implementation _1kze1be_BlockArgs_pfv6jd
@end

typedef void  (^_ListenerTrampoline_1)(id arg0, id arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_1 _1kze1be_wrapListenerBlock_pfv6jd(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_1 weakSelfBlock = nil;
  _ListenerTrampoline_1 strongSelfBlock = [^void(id arg0, id arg1) {
    @autoreleasepool {
      _1kze1be_BlockArgs_pfv6jd* args = [[_1kze1be_BlockArgs_pfv6jd alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_1)(void * waiter, id arg0, id arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_1 _1kze1be_wrapBlockingBlock_pfv6jd(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_1, ^void(id arg0, id arg1), {
    @autoreleasepool {
      _1kze1be_BlockArgs_pfv6jd* args = [[_1kze1be_BlockArgs_pfv6jd alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _1kze1be_BlockArgs_pfv6jd* args = [[_1kze1be_BlockArgs_pfv6jd alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _1kze1be_BlockArgs_18v1jvf : NSObject
@property (copy) id block;
@property void * arg0;
@property (strong) id arg1;
@end
@implementation _1kze1be_BlockArgs_18v1jvf
@end

typedef void  (^_ListenerTrampoline_2)(void * arg0, id arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_2 _1kze1be_wrapListenerBlock_18v1jvf(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_2 weakSelfBlock = nil;
  _ListenerTrampoline_2 strongSelfBlock = [^void(void * arg0, id arg1) {
    @autoreleasepool {
      _1kze1be_BlockArgs_18v1jvf* args = [[_1kze1be_BlockArgs_18v1jvf alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_2)(void * waiter, void * arg0, id arg1);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_2 _1kze1be_wrapBlockingBlock_18v1jvf(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_2, ^void(void * arg0, id arg1), {
    @autoreleasepool {
      _1kze1be_BlockArgs_18v1jvf* args = [[_1kze1be_BlockArgs_18v1jvf alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _1kze1be_BlockArgs_18v1jvf* args = [[_1kze1be_BlockArgs_18v1jvf alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

typedef void  (^_ProtocolTrampoline)(void * sel, id arg1);
__attribute__((visibility("default"))) __attribute__((used))
void  _1kze1be_protocolTrampoline_18v1jvf(id target, void * sel, id arg1) {
  return ((_ProtocolTrampoline)((id (*)(id, SEL, SEL))objc_msgSend)(target, @selector(getDOBJCDartProtocolMethodForSelector:), sel))(sel, arg1);
}

__attribute__((visibility("default")))
@interface _1kze1be_BlockArgs_5ut4yu : NSObject
@property (copy) id block;
@property void * arg0;
@property (strong) id arg1;
@property CBConnectionEvent arg2;
@property (strong) id arg3;
@end
@implementation _1kze1be_BlockArgs_5ut4yu
@end

typedef void  (^_ListenerTrampoline_3)(void * arg0, id arg1, CBConnectionEvent arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_3 _1kze1be_wrapListenerBlock_5ut4yu(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_3 weakSelfBlock = nil;
  _ListenerTrampoline_3 strongSelfBlock = [^void(void * arg0, id arg1, CBConnectionEvent arg2, id arg3) {
    @autoreleasepool {
      _1kze1be_BlockArgs_5ut4yu* args = [[_1kze1be_BlockArgs_5ut4yu alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_3)(void * waiter, void * arg0, id arg1, CBConnectionEvent arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_3 _1kze1be_wrapBlockingBlock_5ut4yu(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_3, ^void(void * arg0, id arg1, CBConnectionEvent arg2, id arg3), {
    @autoreleasepool {
      _1kze1be_BlockArgs_5ut4yu* args = [[_1kze1be_BlockArgs_5ut4yu alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _1kze1be_BlockArgs_5ut4yu* args = [[_1kze1be_BlockArgs_5ut4yu alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

typedef void  (^_ProtocolTrampoline_1)(void * sel, id arg1, CBConnectionEvent arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
void  _1kze1be_protocolTrampoline_5ut4yu(id target, void * sel, id arg1, CBConnectionEvent arg2, id arg3) {
  return ((_ProtocolTrampoline_1)((id (*)(id, SEL, SEL))objc_msgSend)(target, @selector(getDOBJCDartProtocolMethodForSelector:), sel))(sel, arg1, arg2, arg3);
}

__attribute__((visibility("default")))
@interface _1kze1be_BlockArgs_fjrv01 : NSObject
@property (copy) id block;
@property void * arg0;
@property (strong) id arg1;
@property (strong) id arg2;
@end
@implementation _1kze1be_BlockArgs_fjrv01
@end

typedef void  (^_ListenerTrampoline_4)(void * arg0, id arg1, id arg2);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_4 _1kze1be_wrapListenerBlock_fjrv01(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_4 weakSelfBlock = nil;
  _ListenerTrampoline_4 strongSelfBlock = [^void(void * arg0, id arg1, id arg2) {
    @autoreleasepool {
      _1kze1be_BlockArgs_fjrv01* args = [[_1kze1be_BlockArgs_fjrv01 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_4)(void * waiter, void * arg0, id arg1, id arg2);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_4 _1kze1be_wrapBlockingBlock_fjrv01(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_4, ^void(void * arg0, id arg1, id arg2), {
    @autoreleasepool {
      _1kze1be_BlockArgs_fjrv01* args = [[_1kze1be_BlockArgs_fjrv01 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _1kze1be_BlockArgs_fjrv01* args = [[_1kze1be_BlockArgs_fjrv01 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

typedef void  (^_ProtocolTrampoline_2)(void * sel, id arg1, id arg2);
__attribute__((visibility("default"))) __attribute__((used))
void  _1kze1be_protocolTrampoline_fjrv01(id target, void * sel, id arg1, id arg2) {
  return ((_ProtocolTrampoline_2)((id (*)(id, SEL, SEL))objc_msgSend)(target, @selector(getDOBJCDartProtocolMethodForSelector:), sel))(sel, arg1, arg2);
}

__attribute__((visibility("default")))
@interface _1kze1be_BlockArgs_o4q9mk : NSObject
@property (copy) id block;
@property void * arg0;
@property (strong) id arg1;
@property (strong) id arg2;
@property double arg3;
@property BOOL arg4;
@property (strong) id arg5;
@end
@implementation _1kze1be_BlockArgs_o4q9mk
@end

typedef void  (^_ListenerTrampoline_5)(void * arg0, id arg1, id arg2, double arg3, BOOL arg4, id arg5);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_5 _1kze1be_wrapListenerBlock_o4q9mk(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_5 weakSelfBlock = nil;
  _ListenerTrampoline_5 strongSelfBlock = [^void(void * arg0, id arg1, id arg2, double arg3, BOOL arg4, id arg5) {
    @autoreleasepool {
      _1kze1be_BlockArgs_o4q9mk* args = [[_1kze1be_BlockArgs_o4q9mk alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      args.arg4 = arg4;
      args.arg5 = arg5;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_5)(void * waiter, void * arg0, id arg1, id arg2, double arg3, BOOL arg4, id arg5);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_5 _1kze1be_wrapBlockingBlock_o4q9mk(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_5, ^void(void * arg0, id arg1, id arg2, double arg3, BOOL arg4, id arg5), {
    @autoreleasepool {
      _1kze1be_BlockArgs_o4q9mk* args = [[_1kze1be_BlockArgs_o4q9mk alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      args.arg4 = arg4;
      args.arg5 = arg5;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _1kze1be_BlockArgs_o4q9mk* args = [[_1kze1be_BlockArgs_o4q9mk alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      args.arg4 = arg4;
      args.arg5 = arg5;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

typedef void  (^_ProtocolTrampoline_3)(void * sel, id arg1, id arg2, double arg3, BOOL arg4, id arg5);
__attribute__((visibility("default"))) __attribute__((used))
void  _1kze1be_protocolTrampoline_o4q9mk(id target, void * sel, id arg1, id arg2, double arg3, BOOL arg4, id arg5) {
  return ((_ProtocolTrampoline_3)((id (*)(id, SEL, SEL))objc_msgSend)(target, @selector(getDOBJCDartProtocolMethodForSelector:), sel))(sel, arg1, arg2, arg3, arg4, arg5);
}

__attribute__((visibility("default")))
@interface _1kze1be_BlockArgs_8jfq1p : NSObject
@property (copy) id block;
@property void * arg0;
@property (strong) id arg1;
@property (strong) id arg2;
@property (strong) id arg3;
@property (strong) id arg4;
@end
@implementation _1kze1be_BlockArgs_8jfq1p
@end

typedef void  (^_ListenerTrampoline_6)(void * arg0, id arg1, id arg2, id arg3, id arg4);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_6 _1kze1be_wrapListenerBlock_8jfq1p(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_6 weakSelfBlock = nil;
  _ListenerTrampoline_6 strongSelfBlock = [^void(void * arg0, id arg1, id arg2, id arg3, id arg4) {
    @autoreleasepool {
      _1kze1be_BlockArgs_8jfq1p* args = [[_1kze1be_BlockArgs_8jfq1p alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      args.arg4 = arg4;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_6)(void * waiter, void * arg0, id arg1, id arg2, id arg3, id arg4);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_6 _1kze1be_wrapBlockingBlock_8jfq1p(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_6, ^void(void * arg0, id arg1, id arg2, id arg3, id arg4), {
    @autoreleasepool {
      _1kze1be_BlockArgs_8jfq1p* args = [[_1kze1be_BlockArgs_8jfq1p alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      args.arg4 = arg4;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _1kze1be_BlockArgs_8jfq1p* args = [[_1kze1be_BlockArgs_8jfq1p alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      args.arg4 = arg4;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

typedef void  (^_ProtocolTrampoline_4)(void * sel, id arg1, id arg2, id arg3, id arg4);
__attribute__((visibility("default"))) __attribute__((used))
void  _1kze1be_protocolTrampoline_8jfq1p(id target, void * sel, id arg1, id arg2, id arg3, id arg4) {
  return ((_ProtocolTrampoline_4)((id (*)(id, SEL, SEL))objc_msgSend)(target, @selector(getDOBJCDartProtocolMethodForSelector:), sel))(sel, arg1, arg2, arg3, arg4);
}

__attribute__((visibility("default")))
@interface _1kze1be_BlockArgs_1tz5yf : NSObject
@property (copy) id block;
@property void * arg0;
@property (strong) id arg1;
@property (strong) id arg2;
@property (strong) id arg3;
@end
@implementation _1kze1be_BlockArgs_1tz5yf
@end

typedef void  (^_ListenerTrampoline_7)(void * arg0, id arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_7 _1kze1be_wrapListenerBlock_1tz5yf(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_7 weakSelfBlock = nil;
  _ListenerTrampoline_7 strongSelfBlock = [^void(void * arg0, id arg1, id arg2, id arg3) {
    @autoreleasepool {
      _1kze1be_BlockArgs_1tz5yf* args = [[_1kze1be_BlockArgs_1tz5yf alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_7)(void * waiter, void * arg0, id arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_7 _1kze1be_wrapBlockingBlock_1tz5yf(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_7, ^void(void * arg0, id arg1, id arg2, id arg3), {
    @autoreleasepool {
      _1kze1be_BlockArgs_1tz5yf* args = [[_1kze1be_BlockArgs_1tz5yf alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _1kze1be_BlockArgs_1tz5yf* args = [[_1kze1be_BlockArgs_1tz5yf alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

typedef void  (^_ProtocolTrampoline_5)(void * sel, id arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
void  _1kze1be_protocolTrampoline_1tz5yf(id target, void * sel, id arg1, id arg2, id arg3) {
  return ((_ProtocolTrampoline_5)((id (*)(id, SEL, SEL))objc_msgSend)(target, @selector(getDOBJCDartProtocolMethodForSelector:), sel))(sel, arg1, arg2, arg3);
}

__attribute__((visibility("default")))
@interface _1kze1be_BlockArgs_kjpp1d : NSObject
@property (copy) id block;
@property void * arg0;
@property (strong) id arg1;
@property uint16_t arg2;
@property (strong) id arg3;
@end
@implementation _1kze1be_BlockArgs_kjpp1d
@end

typedef void  (^_ListenerTrampoline_8)(void * arg0, id arg1, uint16_t arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_8 _1kze1be_wrapListenerBlock_kjpp1d(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_8 weakSelfBlock = nil;
  _ListenerTrampoline_8 strongSelfBlock = [^void(void * arg0, id arg1, uint16_t arg2, id arg3) {
    @autoreleasepool {
      _1kze1be_BlockArgs_kjpp1d* args = [[_1kze1be_BlockArgs_kjpp1d alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_8)(void * waiter, void * arg0, id arg1, uint16_t arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_8 _1kze1be_wrapBlockingBlock_kjpp1d(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_8, ^void(void * arg0, id arg1, uint16_t arg2, id arg3), {
    @autoreleasepool {
      _1kze1be_BlockArgs_kjpp1d* args = [[_1kze1be_BlockArgs_kjpp1d alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _1kze1be_BlockArgs_kjpp1d* args = [[_1kze1be_BlockArgs_kjpp1d alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

typedef void  (^_ProtocolTrampoline_6)(void * sel, id arg1, uint16_t arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
void  _1kze1be_protocolTrampoline_kjpp1d(id target, void * sel, id arg1, uint16_t arg2, id arg3) {
  return ((_ProtocolTrampoline_6)((id (*)(id, SEL, SEL))objc_msgSend)(target, @selector(getDOBJCDartProtocolMethodForSelector:), sel))(sel, arg1, arg2, arg3);
}
#undef BLOCKING_BLOCK_IMPL

#pragma clang diagnostic pop
