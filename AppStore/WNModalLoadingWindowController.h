#import <Foundation/Foundation.h>
@import UIKit;

@class WNRoundedRectView;

@interface WNModalLoadingWindowController : NSObject
{
    UIWindow *window;

    UIView *backgroundView;
    IBOutlet WNRoundedRectView *loadingView;
    IBOutlet UIActivityIndicatorView *activityIndicatorView;
    IBOutlet UIButton *button;
    IBOutlet UILabel *messageLabel;

    //id delegate;
    BOOL hiding;
}

// ゾンビ化することがあったのでdelegateをretainに。// leakの恐れがあるので weakに。
@property (nonatomic,weak) id delegate;

- (void)showWithTitle:(NSString *)title;
- (void)showWithTitle:(NSString *)title showButton:(BOOL)showButton;
- (void)showWithColor:(NSString *)title showButton:(BOOL)showButton
            fillColor:(UIColor *)fillColor indicatorColor:(UIColor *)indicatorColor;
- (void)hide;
- (IBAction)buttonAction:(id)sender;

@end

@interface NSObject(WNModalLoadingWindowControllerDelegate)
- (void)modalLoadingWindowControllerDidClickButton:(WNModalLoadingWindowController *)modalLoadingWindowController;
- (void)modalLoadingWindowControllerDidHide:(WNModalLoadingWindowController *)modalLoadingWindowController;
@end