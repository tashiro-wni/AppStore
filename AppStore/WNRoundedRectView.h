#import <UIKit/UIKit.h>

@interface WNRoundedRectView : UIView
{
    UIColor *fillColor;
    CGFloat radius;
}

@property (nonatomic, retain) UIColor *fillColor;
@property (nonatomic, assign) CGFloat radius;

@end
