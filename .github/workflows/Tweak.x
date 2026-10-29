#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ReoFix: ảnh bìa KHÔNG vuông (vd. thumbnail YouTube 16:9) -> bỏ nền/viền, bo góc theo ảnh.
// Ảnh vuông (Spotify, bìa album) -> giữ đúng kiểu gốc của Reo.
// Khung thông tin được kéo rộng cho mọi bài. Không đụng vào view của NextUp.

@interface ReoContainerView : UIView
@end

@interface ReoWeakBox : NSObject
@property (nonatomic, weak) UIView *v;
@end
@implementation ReoWeakBox
@end

static const void *kReoClearKey     = &kReoClearKey;      // view/layer đã bị làm trong suốt
static const void *kReoSavedKey     = &kReoSavedKey;      // trạng thái gốc (lưu trên layer)
static const void *kReoModeKey      = &kReoModeKey;       // contentMode gốc của ảnh
static const void *kReoBoxKey       = &kReoBoxKey;        // trỏ về ReoContainerView
static const void *kReoOrigFrameKey = &kReoOrigFrameKey;  // frame gốc của khung thông tin
static const void *kReoAppliedKey   = &kReoAppliedKey;    // frame mình đã đặt
static const void *kReoArtOrigKey    = &kReoArtOrigKey;     // frame gốc của ảnh bìa
static const void *kReoArtAppliedKey = &kReoArtAppliedKey;  // frame ảnh mình đã đặt
static const void *kReoWidenUsedKey  = &kReoWidenUsedKey;   // độ rộng thêm đã dùng
static const void *kReoNextUpKey     = &kReoNextUpKey;      // hàng Next Up đã gắn vào player


static id ReoIvar(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    return iv ? object_getIvar(obj, iv) : nil;
}

static CGFloat ReoCornerRadius(void) {
    CGFloat r = 15;
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("CornerRadius"),
                                                    CFSTR("com.mystery.reopreferences"));
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) {
            double d = 15;
            CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d);
            r = d;
        }
        CFRelease(v);
    }
    return r;
}

// Cài đặt của ReoFix (Cài đặt > ReoFix)
static CGFloat ReoPrefNumber(CFStringRef key, CGFloat def) {
    CGFloat r = def;
    CFPropertyListRef v = CFPreferencesCopyAppValue(key, CFSTR("com.local.reofix"));
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) {
            double d = def;
            CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d);
            r = d;
        }
        CFRelease(v);
    }
    return r;
}
static BOOL ReoPrefBool(CFStringRef key, BOOL def) {
    BOOL r = def;
    CFPropertyListRef v = CFPreferencesCopyAppValue(key, CFSTR("com.local.reofix"));
    if (v) {
        if (CFGetTypeID(v) == CFBooleanGetTypeID()) r = CFBooleanGetValue((CFBooleanRef)v);
        else if (CFGetTypeID(v) == CFNumberGetTypeID()) {
            int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); r = n != 0;
        }
        CFRelease(v);
    }
    return r;
}

static BOOL ReoIsMarked(id o) { return objc_getAssociatedObject(o, kReoClearKey) != nil; }

// Làm trong suốt + lưu trạng thái gốc để trả lại sau
static void ReoMarkClear(UIView *v) {
    CALayer *l = v.layer;
    if (!ReoIsMarked(v)) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        if (v.backgroundColor) d[@"bg"] = v.backgroundColor;
        d[@"bw"]  = @(l.borderWidth);
        d[@"cr"]  = @(l.cornerRadius);
        d[@"mtb"] = @(l.masksToBounds);
        objc_setAssociatedObject(l, kReoSavedKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kReoClearKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(l, kReoClearKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    v.backgroundColor = [UIColor clearColor];
    l.backgroundColor = NULL;
    l.borderWidth = 0;
    l.cornerRadius = 0;
    l.masksToBounds = NO;
}

// Trả lại đúng như Reo đặt
static void ReoUnmark(UIView *v) {
    if (!ReoIsMarked(v)) return;
    CALayer *l = v.layer;
    NSDictionary *d = objc_getAssociatedObject(l, kReoSavedKey);
    objc_setAssociatedObject(v, kReoClearKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(l, kReoClearKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(l, kReoSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIColor *bg = d[@"bg"] ?: d[@"lbg"];
    v.backgroundColor = bg;
    l.borderWidth = [d[@"bw"] doubleValue];
    l.cornerRadius = [d[@"cr"] doubleValue];
    l.masksToBounds = [d[@"mtb"] boolValue];
    l.mask = nil;
}

// View của tweak NextUp (NUNextUpRowView...): tuyệt đối không đụng vào
static BOOL ReoIsNextUpClass(UIView *v) {
    const char *n = class_getName(object_getClass(v));
    return n && strncmp(n, "NU", 2) == 0;
}
static BOOL ReoHasNextUp(UIView *v, int depth) {
    if (ReoIsNextUpClass(v)) return YES;
    if (depth <= 0) return NO;
    for (UIView *s in v.subviews) {
        if (ReoHasNextUp(s, depth - 1)) return YES;
    }
    return NO;
}

static BOOL ReoClose(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) < 6 && fabs(a.origin.y - b.origin.y) < 6 &&
           fabs(a.size.width - b.size.width) < 6 && fabs(a.size.height - b.size.height) < 6;
}

static void ReoCollectImageViews(UIView *v, NSMutableArray *out) {
    for (UIView *s in v.subviews) {
        if (ReoIsNextUpClass(s)) continue;
        if ([s isKindOfClass:[UIImageView class]] &&
            s.bounds.size.width >= 120 && ((UIImageView *)s).image) {
            [out addObject:s];
        }
        ReoCollectImageViews(s, out);
    }
}

// Bo góc đúng vùng ảnh thật (aspect-fit) bằng mask
static void ReoRoundImageRect(UIImageView *iv) {
    if (ReoHasNextUp(iv, 2)) return;
    CGSize is = iv.image.size, bs = iv.bounds.size;
    if (is.width <= 0 || is.height <= 0 || bs.width <= 0 || bs.height <= 0) return;
    CGFloat sc = MIN(bs.width / is.width, bs.height / is.height);
    CGSize fit = CGSizeMake(is.width * sc, is.height * sc);
    CGRect r = CGRectMake((bs.width - fit.width) / 2, (bs.height - fit.height) / 2,
                          fit.width, fit.height);
    CGFloat radius = MIN(ReoCornerRadius(), MIN(fit.width, fit.height) / 2);
    CAShapeLayer *m = [CAShapeLayer layer];
    m.path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius].CGPath;
    iv.layer.mask = m;
}

static BOOL ReoAlreadyApplied(UIView *v) {
    NSValue *a = objc_getAssociatedObject(v, kReoAppliedKey);
    return a && CGRectEqualToRect(v.frame, [a CGRectValue]);
}

// Khung thông tin: kéo rộng ra hai bên (áp dụng cho mọi bài)
static void ReoReshapePanel(UIView *container, BOOL apply) {
    UIView *bg = ReoIvar(container, "_reoMiniBackgroundView");
    if (![bg isKindOfClass:[UIView class]] || !bg.superview) return;
    if (!apply) {
        NSValue *o = objc_getAssociatedObject(bg, kReoOrigFrameKey);
        if (o && ReoAlreadyApplied(bg)) bg.frame = [o CGRectValue];
        objc_setAssociatedObject(bg, kReoOrigFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bg, kReoAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    CGFloat want = ReoPrefNumber(CFSTR("panelWiden"), 12);
    CGRect f = bg.frame;
    if (ReoAlreadyApplied(bg)) {
        NSNumber *used = objc_getAssociatedObject(bg, kReoWidenUsedKey);
        NSValue *o = objc_getAssociatedObject(bg, kReoOrigFrameKey);
        if (!o || (used && fabs(used.doubleValue - want) < 0.5)) return;
        f = [o CGRectValue];            // giá trị đổi -> tính lại từ frame gốc
    }
    if (f.size.width < container.bounds.size.width * 0.5 || f.size.height < 130) return;
    objc_setAssociatedObject(bg, kReoOrigFrameKey, [NSValue valueWithCGRect:f],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat d = MIN(want, MAX(0, f.origin.x - 6));
    f.origin.x -= d;
    f.size.width += 2 * d;
    bg.frame = f;
    objc_setAssociatedObject(bg, kReoAppliedKey, [NSValue valueWithCGRect:bg.frame],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bg, kReoWidenUsedKey, @(want), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ReoProcessImage(UIView *container, UIImageView *iv, BOOL apply, BOOL maximized) {
    if (!apply) {
        // Trả frame ảnh về như Reo đặt (trước khi dò khung bao quanh)
        NSValue *orig = objc_getAssociatedObject(iv, kReoArtOrigKey);
        NSValue *ap = objc_getAssociatedObject(iv, kReoArtAppliedKey);
        if (orig && ap && CGRectEqualToRect(iv.frame, [ap CGRectValue])) {
            iv.frame = [orig CGRectValue];
        }
        objc_setAssociatedObject(iv, kReoArtOrigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(iv, kReoArtAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSMutableArray *chain = [NSMutableArray arrayWithObject:iv];
    for (UIView *p = iv.superview; p && p != container; p = p.superview) {
        if (CGRectGetWidth(p.bounds) > CGRectGetWidth(iv.bounds) + 40) break;
        if (ReoHasNextUp(p, 3)) break;
        [chain addObject:p];
    }
    for (UIView *s in iv.superview.subviews) {
        if (s != iv && ![s isKindOfClass:[UILabel class]] && !ReoHasNextUp(s, 3) &&
            ReoClose(s.frame, iv.frame)) {
            [chain addObject:s];
        }
    }

    if (apply) {
        if (!objc_getAssociatedObject(iv, kReoModeKey)) {
            objc_setAssociatedObject(iv, kReoModeKey, @(iv.contentMode),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (UIView *v in chain) ReoMarkClear(v);
        iv.contentMode = UIViewContentModeScaleAspectFit;

        // Khung ảnh = đúng tỉ lệ ảnh, rộng theo Cài đặt > ReoFix,
        // giữ nguyên tâm cũ. Lưu frame gốc để trả lại khi gặp ảnh vuông.
        CGSize is = iv.image.size;
        NSValue *ap = objc_getAssociatedObject(iv, kReoArtAppliedKey);
        if (!(ap && CGRectEqualToRect(iv.frame, [ap CGRectValue]))) {
            objc_setAssociatedObject(iv, kReoArtOrigKey, [NSValue valueWithCGRect:iv.frame],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGRect o = [objc_getAssociatedObject(iv, kReoArtOrigKey) CGRectValue];
        if (maximized && is.width > 0 && is.height > 0 && o.size.width >= 200) {   // chỉ phóng ở chế độ lớn
            CGFloat W = MIN(ReoPrefNumber(CFSTR("artworkWidth"), 350),
                            [UIScreen mainScreen].bounds.size.width);
            CGFloat H = W * is.height / is.width;
            iv.frame = CGRectMake(CGRectGetMidX(o) - W / 2, CGRectGetMidY(o) - H / 2, W, H);
            objc_setAssociatedObject(iv, kReoArtAppliedKey, [NSValue valueWithCGRect:iv.frame],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            // Thu nhỏ / ẩn: giữ nguyên khung của Reo (không phóng, không tràn ra ngoài)
            NSValue *ap2 = objc_getAssociatedObject(iv, kReoArtAppliedKey);
            NSValue *or2 = objc_getAssociatedObject(iv, kReoArtOrigKey);
            if (ap2 && or2 && CGRectEqualToRect(iv.frame, [ap2 CGRectValue])) {
                iv.frame = [or2 CGRectValue];
            }
            objc_setAssociatedObject(iv, kReoArtAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(iv, kReoArtOrigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        ReoRoundImageRect(iv);
    } else {
        for (UIView *v in chain) ReoUnmark(v);
        NSNumber *m = objc_getAssociatedObject(iv, kReoModeKey);
        if (m) {
            iv.contentMode = (UIViewContentMode)m.integerValue;
            objc_setAssociatedObject(iv, kReoModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        iv.layer.mask = nil;
    }
}

// Gắn hàng "Up Next" của NextUp 3 (class NUNextUpRowView) vào player của Reo,
// đặt ngay phía trên khung thông tin. Chỉ hiện ở chế độ lớn và khi NextUp có bài kế tiếp.
static void ReoUpdateNextUp(UIView *container, BOOL show) {
    UIView *row = objc_getAssociatedObject(container, kReoNextUpKey);
    Class rowClass = objc_getClass("NUNextUpRowView");
    UIView *bg = ReoIvar(container, "_reoMiniBackgroundView");
    BOOL maximized = [bg isKindOfClass:[UIView class]] && bg.superview &&
                     bg.frame.size.width >= container.bounds.size.width * 0.5 &&
                     bg.frame.size.height >= 130;
    if (!rowClass || !show || !maximized) {
        if (row) row.hidden = YES;
        return;
    }
    if (!row) {
        row = [[rowClass alloc] initWithFrame:CGRectMake(0, 0, 320, 64)];
        objc_setAssociatedObject(container, kReoNextUpKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (row.superview != bg.superview) [bg.superview addSubview:row];

    SEL refreshSel = NSSelectorFromString(@"refreshFromManager");
    if ([row respondsToSelector:refreshSel]) {
        ((void (*)(id, SEL))objc_msgSend)(row, refreshSel);
    }
    BOOL has = YES;
    SEL hasSel = NSSelectorFromString(@"hasContent");
    if ([row respondsToSelector:hasSel]) {
        has = ((BOOL (*)(id, SEL))objc_msgSend)(row, hasSel);
    }
    CGFloat h = 64;
    SEL hSel = NSSelectorFromString(@"preferredHeight");
    if ([rowClass respondsToSelector:hSel]) {
        h = ((CGFloat (*)(id, SEL))objc_msgSend)(rowClass, hSel);
    }
    CGRect pf = bg.frame;
    row.frame = CGRectMake(pf.origin.x, pf.origin.y - h - 8, pf.size.width, h);
    row.hidden = !has;
    [row.superview bringSubviewToFront:row];
}

// Chỉ coi là "chế độ lớn" khi: khung thông tin rộng gần hết màn hình, chưa trượt xuống
// dưới đáy (dismissed), và ảnh bìa nằm phía trên khung. Các chế độ khác (thu nhỏ, ẩn)
// ReoFix không đụng vào để Reo tự xử lý như bình thường.
static BOOL ReoIsMaximized(UIView *container) {
    UIView *bg = ReoIvar(container, "_reoMiniBackgroundView");
    if (![bg isKindOfClass:[UIView class]] || !bg.superview) return NO;
    CGRect sb = [UIScreen mainScreen].bounds;
    CGRect bf = [bg.superview convertRect:bg.frame toView:nil];
    if (bf.size.width < sb.size.width * 0.6 || bf.size.height < 130) return NO;
    if (bf.origin.y > sb.size.height * 0.85) return NO;          // đã trượt xuống đáy
    UIImageView *art = ReoIvar(container, "_artworkImageView");
    if ([art isKindOfClass:[UIImageView class]] && art.superview) {
        CGRect af = [art.superview convertRect:art.frame toView:nil];
        if (CGRectGetMaxY(af) > bf.origin.y + 20) return NO;      // ảnh phải nằm trên khung
    }
    return YES;
}

static void ReoFixContainer(UIView *container) {
    NSMutableArray *views = [NSMutableArray array];
    UIImageView *art = ReoIvar(container, "_artworkImageView");
    if ([art isKindOfClass:[UIImageView class]] && art.image) {
        [views addObject:art];
    } else {
        ReoCollectImageViews(container, views);
    }

    BOOL enabled = ReoPrefBool(CFSTR("enabled"), YES);
    BOOL maximized = ReoIsMaximized(container);
    BOOL active = enabled && maximized;   // phóng ảnh, kéo rộng khung, Next Up: chỉ ở chế độ lớn
    for (UIImageView *iv in views) {
        if (!objc_getAssociatedObject(iv, kReoBoxKey)) {
            ReoWeakBox *box = [ReoWeakBox new];
            box.v = container;
            objc_setAssociatedObject(iv, kReoBoxKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGSize is = iv.image.size;
        if (is.height <= 0) continue;
        BOOL nonSquare = fabs(is.width / is.height - 1.0) > 0.05;
        ReoProcessImage(container, iv, nonSquare && enabled, maximized);   // phần nhìn: mọi chế độ
    }
    ReoReshapePanel(container, active);   // khung thông tin: áp dụng cho mọi bài (chế độ lớn)
    ReoUpdateNextUp(container, active && ReoPrefBool(CFSTR("showNextUp"), YES));
}

%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    if (ReoIsMarked(self)) {
        NSMutableDictionary *d = objc_getAssociatedObject(self.layer, kReoSavedKey);
        if (color && d && CGColorGetAlpha(color.CGColor) > 0.01) d[@"bg"] = color;
        color = [UIColor clearColor];
    }
    %orig(color);
}
%end

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (ReoIsMarked(self)) {
        NSMutableDictionary *d = objc_getAssociatedObject(self, kReoSavedKey);
        if (color && d && !d[@"bg"] && CGColorGetAlpha(color) > 0.01) {
            d[@"lbg"] = [UIColor colorWithCGColor:color];
        }
        color = NULL;
    }
    %orig(color);
}
- (void)setBorderWidth:(CGFloat)w {
    if (ReoIsMarked(self)) {
        NSMutableDictionary *d = objc_getAssociatedObject(self, kReoSavedKey);
        if (d && w > 0) d[@"bw"] = @(w);
        w = 0;
    }
    %orig(w);
}
%end

// Đổi bài mà container không layout lại -> vẫn cập nhật khi ảnh đổi
%hook UIImageView
- (void)setImage:(UIImage *)image {
    %orig;
    ReoWeakBox *b = objc_getAssociatedObject(self, kReoBoxKey);
    UIView *c = b.v;
    if (c) {
        dispatch_async(dispatch_get_main_queue(), ^{ ReoFixContainer(c); });
    }
}
%end

%group ReoHooks
%hook ReoContainerView
- (void)layoutSubviews {
    %orig;
    ReoFixContainer(self);
}
- (void)didMoveToWindow {
    %orig;
    ReoFixContainer(self);
}
%end
%end

static void ReoTryInit(void) {
    static BOOL inited = NO;
    if (inited || !objc_getClass("ReoContainerView")) return;
    inited = YES;
    %init(ReoHooks);
}

%ctor {
    %init;
    ReoTryInit();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{ ReoTryInit(); });
}
