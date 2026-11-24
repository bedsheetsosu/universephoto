// PRIVATE macOS API – not documented by Äbbl.
//
// CoreGraphics ships these classes (used by Sidecar/AirPlay) but publishes no header. The
// declarations below mirror what open-source projects such as DeskPad use. They are only needed
// for Tafel's optional "Zweiter Bildschirm" mode; every other mode uses public API only.
// Äbbl may change or remove this at any time – Tafel then reports that the mode is unavailable.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// weak_import: if a future macOS drops one of these classes, UniversePen Host still launches (the class
// reference is simply nil) instead of failing at load time. VirtualDisplay.availability checks
// every class and method before anything is called.
#define TAFEL_WEAK __attribute__((weak_import))

@class CGVirtualDisplay;

TAFEL_WEAK
@interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nonatomic, nullable) dispatch_queue_t queue;
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int serialNum;
@property (copy, nonatomic, nullable) void (^terminationHandler)(id _Nullable, CGVirtualDisplay * _Nullable);
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end

TAFEL_WEAK
@interface CGVirtualDisplayMode : NSObject
@property (readonly, nonatomic) unsigned int width;
@property (readonly, nonatomic) unsigned int height;
@property (readonly, nonatomic) double refreshRate;
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

TAFEL_WEAK
@interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) unsigned int hiDPI;
@end

TAFEL_WEAK
@interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) CGDirectDisplayID displayID;
- (nullable instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

NS_ASSUME_NONNULL_END
