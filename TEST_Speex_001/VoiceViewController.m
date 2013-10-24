//
//  VoiceViewController.m
//  VoiceChat
//
//  Created by cai xuejun on 12-10-18.
//  Copyright (c) 2012年 caixuejun. All rights reserved.
//

#import "VoiceViewController.h"

@interface VoiceViewController ()

@property (copy, nonatomic) NSString *folderPath;

@end

static NSString *dateString() 
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateFormat = @"ddMMMYY_hhmmssa";
	return [[formatter stringFromDate:[NSDate date]] stringByAppendingString:@".spx"];
}

@implementation VoiceViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)dealloc 
{
    [self unregisterForAudioQueueNotifications];
}

- (void)viewDidLoad 
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    [self registerForAudioQueueNotifications];
    _intercom = [[SpeexManager alloc] init];
    self.intercom.delegate = self;
    
    self.voices = [NSMutableArray array];
    
    // 这里是创建一个储存AMR文件的文件夹
    NSString *folderPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"spx"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    BOOL creatFolderSuccessfully = [fileManager createDirectoryAtPath:folderPath
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error];
    if (creatFolderSuccessfully) {
        self.folderPath = folderPath;
    } else {
        NSLog(@"Err :%@", [error localizedDescription]);
    }
}

- (IBAction)touchDown:(id)sender {
    NSString *filePath = [self.folderPath stringByAppendingPathComponent:dateString()];
    NSFileManager *fileManager = [NSFileManager defaultManager];    
    BOOL creatFileSuccessfully = [fileManager createFileAtPath:filePath
                                                      contents:nil
                                                    attributes:nil];
    if (creatFileSuccessfully) {
        NSError *error;
        BOOL success = [self.intercom startRecordingWithSpeexFilePath:filePath
                                                                error:&error];
        if (success == NO) {
            NSLog(@"Err : %@", [error localizedDescription]);
        }
    }
}

- (IBAction)touchUp:(id)sender {
    NSError *error;
    BOOL success = [self.intercom stopRecording:&error];
    if (success == NO) {
        NSLog(@"Err : %@", [error localizedDescription]);
    }
    self.progressView.progress = 0;
    self.label.text = @" ";
}

- (IBAction)pop:(id)sender {
    if ([self.intercom isPlaying]) {
        [self.intercom stopPlaying:nil];
    }
    [self dismissModalViewControllerAnimated:YES];
}

- (void)playRecording:(NSString *)filePath {
    NSError *err1;
    BOOL success = [self.intercom startPlayingWithSpeexFilePath:filePath error:&err1];
    if (success == NO) {
        NSLog(@"Err : %@", [err1 localizedDescription]);
    }
    NSError *err2;
    float time = [self.intercom calculatePlayTime:filePath error:&err2];
    if (time < 0) {
        self.label.text = @"";
        NSLog(@"Err : %@", [err2 localizedDescription]);
    } else {
        self.label.text = [NSString stringWithFormat:@"%.f", time];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidUnload {
    [self setTableView:nil];
    [self setProgressView:nil];
    [self setLabel:nil];
    [super viewDidUnload];
}

#pragma -mark AMRRecordDelegate
// 刷新说话分贝数
- (void)recordStatusWithCurrentTime:(float)time {
    self.label.text = [NSString stringWithFormat:@"%.f", time];
}
// 刷新录音时间
- (void)recordingStatusWithMeter:(float)meter {
    self.progressView.progress = meter;
}

// 时间超过1秒
- (void)recordingInTime {
    NSLog(@"你的录音已经有效！");
}

// 录音时间过短
- (void)recordingTimeTooShort {
    self.progressView.progress = 0;
}

// 录音时间过长
- (void)recordingTimeTooLong {
    NSLog(@"record time too long...");
}

// 发送文档
- (void)didFinishedRecording:(NSString *)filePath {
    NSLog(@"录音完毕...");
    self.progressView.progress = 0;
    self.label.text = @" ";
    [self.voices addObject:filePath];
    [self.tableView reloadData];
}

- (void)finishPlaying
{
    NSLog(@"播放完毕");
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    return [self.voices count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }
    
    cell.textLabel.text = [[self.voices objectAtIndex:indexPath.row] lastPathComponent];
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *filePath = [self.voices objectAtIndex:indexPath.row];
    [self playRecording:filePath];
}

#pragma mark - playback queue notifications
- (void)registerForAudioQueueNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(recordbackQueueStarted)
                                                 name:kInputAudioQueueStarted
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(recordbackQueueStopped)
                                                 name:kInputAudioQueueStopped
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playbackQueueStarted)
                                                 name:kOutputAudioQueueStarted
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playbackQueueStopped)
                                                 name:kOutputAudioQueueStopped
                                               object:nil];
}

- (void)unregisterForAudioQueueNotifications {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kInputAudioQueueStarted
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kInputAudioQueueStopped
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kOutputAudioQueueStarted
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kOutputAudioQueueStopped
                                                  object:nil];
}

#pragma mark - notification functions
- (void)playbackQueueStarted {
    NSLog(@"播放开始");
}

- (void)playbackQueueStopped {
    NSLog(@"播放结束");
}

- (void)recordbackQueueStarted {
    NSLog(@"录音开始");
}

- (void)recordbackQueueStopped {
    NSLog(@"录音结束");
}

@end
