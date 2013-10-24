//
//  MediaCodec.h
//  TEST_Speex_001
//
//  Created by cxjwin on 13-6-28.
//  Copyright (c) 2013年 caixuejun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "SpeexRecorder.h"
#import "SpeexPlayer.h"

#define kTimeInterval1 0.1
#define kTimeInterval2 1.0
#define kTimeLimitShort 1.0
#define kTimeLimitLong 60.0

@protocol SpeexDelegate <NSObject>
@optional
- (void)recordingInTime;
- (void)recordingTimeTooShort;
- (void)recordingTimeTooLong;
- (void)didFinishedRecording:(NSString *)filePath;

- (void)recordingStatusWithMeter:(float)meter;
- (void)recordingStatusWithCurrentTime:(float)time;

- (void)audioSessionRouteHasChanged:(SInt32)reasonVal;

@end

@interface SpeexManager : NSObject
@property (assign, nonatomic) id<SpeexDelegate> delegate;
@property (retain, nonatomic) SpeexRecorder *speexRecorder;
@property (retain, nonatomic) SpeexPlayer *speexPlayer;

@property (copy, nonatomic) NSString *recorderFilePath;
@property (copy, nonatomic) NSString *playerFilePath;

@property (assign, nonatomic, getter = inputIsAvailable) UInt32 inputIsAvailable;
@property (assign, nonatomic) double minRecordingTime;
@property (assign, nonatomic) double maxRecordingTime;

@property (retain, nonatomic) NSTimer *timerMeter;
@property (retain, nonatomic) NSTimer *timerCurrentTime;

- (BOOL)startRecordingWithSpeexFilePath:(NSString *)filePath error:(NSError **)error;
- (BOOL)stopRecording:(NSError **)error;

- (BOOL)startPlayingWithSpeexFilePath:(NSString *)filePath error:(NSError **)error;
- (BOOL)stopPlaying:(NSError **)error;

- (double)calculatePlayTime:(NSString *)filePath error:(NSError **)error;

- (BOOL)isRecording;
- (BOOL)isPlaying;

- (UInt32)inputIsAvailable;

@end