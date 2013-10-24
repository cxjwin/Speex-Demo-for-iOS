//
//  MediaCodec.h
//  TEST_Speex_001
//
//  Created by cxjwin on 13-6-28.
//  Copyright (c) 2013年 caixuejun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include "SpeexAllHeader.h"

#define kNumberBuffers 3

#define kInputAudioQueueStarted @"kInputAudioQueueStarted"
#define kInputAudioQueueStopped @"kInputAudioQueueStopped"
#define kSpeexErrorDomain @"com.cxjwin.speex_demo"

typedef NS_ENUM(NSInteger, SpeexErrorCode) {
    SpeexFileError = 1001,
};

@interface SpeexRecorder : NSObject 
{
    AudioStreamBasicDescription dataFormat;
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[kNumberBuffers];
    
    FILE *fp;
    void *encoder;
    SpeexPreprocessState *preprocessState;
}

@property (assign, nonatomic) BOOL isRecording;

- (float)averagePower;
- (float)peakPower;
- (float)currentTime;

- (BOOL)startRecordingWithSpeexFilePath:(NSString *)amrFilePath error:(NSError **)error;
- (BOOL)stopRecording:(NSError **)error;

@end