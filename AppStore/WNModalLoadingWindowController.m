#import <QuartzCore/QuartzCore.h>

#import "WNModalLoadingWindowController.h"
#import "WNRoundedRectView.h"

static const CFTimeInterval SHOW_DURATION = 0.4;
static const CFTimeInterval HIDE_DURATION = 0.2;

@implementation WNModalLoadingWindowController

#pragma mark init / dealloc

@synthesize delegate;

- (id)init
{
	//FRLogSelfAndCommand();
    self = [super init];
    if(self != nil) {
        [[NSBundle mainBundle] loadNibNamed:@"WNModalLoadingWindowController" owner:self options:nil];

        window.backgroundColor = [UIColor clearColor];
        window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        window.windowLevel = UIWindowLevelNormal + 1;

        backgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, window.frame.size.width, window.frame.size.height)];
        backgroundView.opaque = NO;
        backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
        
        [window addSubview:backgroundView];

        loadingView.backgroundColor = [UIColor clearColor];
        loadingView.fillColor = [UIColor colorWithWhite:0.0f alpha:0.7f];

        [window addSubview:loadingView];
    }
    return self;
}

- (void)dealloc
{
    [button cancelTrackingWithEvent:nil];
}

#pragma mark CAAnimation delegate

- (void)animationDidStop:(CAAnimation *)theAnimation finished:(BOOL)flag
{
	//FRLogSelfAndCommand();
    NSString *context = [theAnimation valueForKey:@"context"];
    //FRLogSelfAndCommand();
    //FRLog(@"context:%@", context);
    
    if([context isEqualToString:@"show"]) {
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        [activityIndicatorView startAnimating];
    } else if([context isEqualToString:@"hide"]) {
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        if(delegate && [delegate respondsToSelector:@selector(modalLoadingWindowControllerDidHide:)]) {
            [delegate modalLoadingWindowControllerDidHide:self];
        }
        window.hidden = YES;
        hiding = NO;
    }
}

#pragma mark show

- (void)showAnimation
{
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    CAKeyframeAnimation *scaleAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    
    scaleAnimation.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.0f],
                             [NSNumber numberWithFloat:1.1f],
                             [NSNumber numberWithFloat:0.9f],
                             [NSNumber numberWithFloat:1.0f],
                             nil];
    
    scaleAnimation.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.0f],
                               [NSNumber numberWithFloat:0.5f],
                               [NSNumber numberWithFloat:0.75f],
                               [NSNumber numberWithFloat:1.0f],
                               nil];
    
    scaleAnimation.timingFunctions = [NSArray arrayWithObjects:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                                      [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                                      [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                                      nil];
    
    scaleAnimation.calculationMode = kCAAnimationLinear;
    scaleAnimation.duration = SHOW_DURATION;
    scaleAnimation.delegate = self;
    [scaleAnimation setValue:@"show" forKey:@"context"];

    [loadingView.layer addAnimation:scaleAnimation forKey:@"scale"];
    
    CABasicAnimation *opacityAnimation;
    opacityAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacityAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    opacityAnimation.fromValue = [NSNumber numberWithFloat:0.0f];
    opacityAnimation.toValue = [NSNumber numberWithFloat:1.0f];
    opacityAnimation.duration = SHOW_DURATION;
    [loadingView.layer addAnimation:opacityAnimation forKey:@"opacityAnimation"];

    [backgroundView.layer addAnimation:opacityAnimation forKey:@"opacityAnimation"];
}

- (void)showWithTitle:(NSString *)title showButton:(BOOL)showButton
{
	//FRLogSelfAndCommand();
    NSLog(@"%s, %@", __FUNCTION__, title);
    messageLabel.text = title;
    [messageLabel setNeedsDisplay];

    CGRect frame = loadingView.frame;

    if(showButton == NO) {
        [button removeFromSuperview];
        frame.size.height -= 60;
        loadingView.frame = frame;
        [activityIndicatorView startAnimating];
    }
    
    frame.origin.x = floorf((backgroundView.frame.size.width - loadingView.frame.size.width) / 2.0f);
    frame.origin.y = floorf((backgroundView.frame.size.height - loadingView.frame.size.height) / 2.0f);
    loadingView.frame = frame;

    [window makeKeyAndVisible];
    
    [self showAnimation];
}

- (void)showWithTitle:(NSString *)title
{
    [self showWithTitle:title showButton:YES];
}

- (void)showWithColor:(NSString *)title showButton:(BOOL)showButton
            fillColor:(UIColor *)fillColor indicatorColor:(UIColor *)indicatorColor
{
    CGRect frame = loadingView.frame;
    
    if(showButton == NO) {
        [button removeFromSuperview];
        frame.size.height -= 60;
        loadingView.frame = frame;
        [activityIndicatorView startAnimating];
    }
    
    if([title length] > 0){
        messageLabel.text = title;
    }else{
        messageLabel.hidden = YES;
    }

    loadingView.fillColor = fillColor;
    float ios_version = [[[UIDevice currentDevice] systemVersion] floatValue];
    if( ios_version >= 5.0 ){
        activityIndicatorView.color = indicatorColor;
    }
    
    frame.origin.x = floorf((backgroundView.frame.size.width - loadingView.frame.size.width) / 2.0f);
    frame.origin.y = floorf((backgroundView.frame.size.height - loadingView.frame.size.height) / 2.0f);
    loadingView.frame = frame;
    
    [window makeKeyAndVisible];
    
    [self showAnimation];
}

- (void)hide
{
    //FRLogSelfAndCommand();
    //FRLog(@"hiding=%d", hiding);

    if(hiding == YES) {
        return;
    }
    hiding = YES;

    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    CABasicAnimation *opacityAnimation;
    opacityAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacityAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    opacityAnimation.fromValue = [NSNumber numberWithFloat:1.0f];
    opacityAnimation.toValue = [NSNumber numberWithFloat:0.0f];
    opacityAnimation.duration = HIDE_DURATION;

    opacityAnimation.delegate = self;
    [opacityAnimation setValue:@"hide" forKey:@"context"];

    [window.layer addAnimation:opacityAnimation forKey:@"opacityAnimation"];

    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    window.layer.opacity = 0.0f;
    [CATransaction commit];

    button.enabled = NO;
    [button cancelTrackingWithEvent:nil];
    [activityIndicatorView stopAnimating];
}

#pragma mark action

- (IBAction)buttonAction:(id)sender
{
    //FRLogSelfAndCommand();
    //FRLog(@"hiding=%d", hiding);

    //FRLogSelfAndCommand();
    if(delegate && [delegate respondsToSelector:@selector(modalLoadingWindowControllerDidClickButton:)]) {
        [delegate modalLoadingWindowControllerDidClickButton:self];
    }
    
    [self hide];
}

@end
