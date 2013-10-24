//
//  ViewController.m
//  TEST_Speex_001
//
//  Created by cai xuejun on 12-9-3.
//  Copyright (c) 2012年 caixuejun. All rights reserved.
//

#import "ViewController.h"
#import "VoiceViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    UIButton *button = (UIButton *)[self.view viewWithTag:101];
    [button addTarget:self action:@selector(push:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)push:(id)sender 
{
    VoiceViewController *viewController = [[VoiceViewController alloc] init];
    [self presentModalViewController:viewController animated:YES];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

@end
