// DiscordEchoUI: قائمة عائمة للتحكم بشدة الصدى (0 - 100)
// زر 🎙 تسحبه في الشاشة، والضغط عليه يفتح القائمة.

#import <UIKit/UIKit.h>
#include <math.h>

extern void DiscordEcho_SetLevel(int level);

static NSString *const kLevelKey = @"DiscordEchoLevel";

// نافذة شفافة تمرر اللمس لديسكورد إلا لما تلمس الزر أو القائمة
@interface EchoWindow : UIWindow
@end

@implementation EchoWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface EchoController : UIViewController
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@end

@implementation EchoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    int level = [d objectForKey:kLevelKey] ? (int)[d integerForKey:kLevelKey] : 50;

    // الزر العائم
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    fab.layer.cornerRadius = 26;
    fab.layer.borderWidth = 1;
    fab.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    [fab setTitle:@"🎙" forState:UIControlStateNormal];
    fab.titleLabel.font = [UIFont systemFontOfSize:24];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)];
    [fab addGestureRecognizer:pan];
    [self.view addSubview:fab];
    self.fab = fab;

    // القائمة
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 270, 130)];
    panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    panel.layer.cornerRadius = 16;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, 238, 28)];
    val.textAlignment = NSTextAlignmentCenter;
    val.textColor = UIColor.whiteColor;
    val.font = [UIFont boldSystemFontOfSize:18];
    [panel addSubview:val];
    self.valueLabel = val;

    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(16, 56, 238, 30)];
    s.minimumValue = 0;
    s.maximumValue = 100;
    s.continuous = YES;
    s.value = level;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:s];
    self.slider = s;

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(16, 94, 238, 20)];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    hint.font = [UIFont systemFontOfSize:12];
    hint.text = @"0 = إيقاف  ·  100 = أقوى صدى";
    [panel addSubview:hint];

    [self updateLabel:level];
    DiscordEcho_SetLevel(level);
}

- (void)updateLabel:(int)level {
    self.valueLabel.text = (level == 0)
        ? @"الصدى: متوقف"
        : [NSString stringWithFormat:@"شدة الصدى: %d", level];
}

- (void)sliderChanged:(UISlider *)sender {
    int level = (int)lroundf(sender.value);
    DiscordEcho_SetLevel(level);
    [[NSUserDefaults standardUserDefaults] setInteger:level forKey:kLevelKey];
    [self updateLabel:level];
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    if (!self.panel.hidden) [self positionPanel];
}

- (void)positionPanel {
    CGRect b = self.view.bounds;
    CGFloat w = 270, h = 130;
    CGFloat x = CGRectGetMidX(self.fab.frame) - w / 2;
    x = MAX(10, MIN(x, b.size.width - w - 10));
    CGFloat y = CGRectGetMaxY(self.fab.frame) + 10;
    if (y + h > b.size.height - 10) y = CGRectGetMinY(self.fab.frame) - h - 10;
    self.panel.frame = CGRectMake(x, y, w, h);
}

- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.view];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.view];
    [self clampFab];
    if (!self.panel.hidden) [self positionPanel];
}

- (void)clampFab {
    CGRect b = self.view.bounds;
    UIEdgeInsets s = self.view.safeAreaInsets;
    CGFloat r = 26;
    CGPoint c = self.fab.center;
    c.x = MAX(r + s.left, MIN(c.x, b.size.width - r - s.right));
    c.y = MAX(r + s.top,  MIN(c.y, b.size.height - r - s.bottom));
    self.fab.center = c;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self clampFab];
    if (!self.panel.hidden) [self positionPanel];
}

@end

static EchoWindow *gWin;

static void echo_setup_window(void) {
    if (gWin) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;
    gWin = [[EchoWindow alloc] initWithWindowScene:scene];
    gWin.windowLevel = UIWindowLevelAlert + 100;
    gWin.backgroundColor = UIColor.clearColor;
    gWin.rootViewController = [EchoController new];
    gWin.hidden = NO;
}

__attribute__((constructor))
static void echo_ui_init(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    int level = [d objectForKey:kLevelKey] ? (int)[d integerForKey:kLevelKey] : 50;
    DiscordEcho_SetLevel(level);

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { echo_setup_window(); }];
}
