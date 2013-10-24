//
//  VoiceViewController.h
//  VoiceChat
//
//  Created by cai xuejun on 12-10-18.
//  Copyright (c) 2012年 caixuejun. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SpeexManager.h"

@interface VoiceViewController : UIViewController<SpeexDelegate>

@property (retain, nonatomic) IBOutlet UITableView *tableView;
@property (retain, nonatomic) IBOutlet UIProgressView *progressView;
@property (retain, nonatomic) IBOutlet UILabel *label;

@property (retain, nonatomic) NSMutableArray *voices;
@property (retain, nonatomic) SpeexManager *intercom;

@end
