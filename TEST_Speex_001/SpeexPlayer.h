//
//  SpeexPlayer.h
//  TEST_Speex_001
//
//  Created by cxjwin on 13-6-28.
//  Copyright (c) 2013年 caixuejun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "SpeexAllHeader.h"

#define kNumberBuffers 3

#define kOutputAudioQueueStarted @"kOutputAudioQueueStarted"
#define kOutputAudioQueueStopped @"kOutputAudioQueueStopped"
#define kSpeexErrorDomain @"com.cxjwin.speex_demo"

@interface SpeexPlayer : NSObject
{
    AudioStreamBasicDescription dataFormat;
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[kNumberBuffers];
    
    FILE *fp;
    void *decoder;
}

@property (assign, nonatomic) BOOL isPlaying;
@property (readonly, nonatomic) OSStatus initStatus;

- (BOOL)startPlayingWithSpeexFilePath:(NSString *)amrFilePath error:(NSError **)error;
- (BOOL)stopPlaying:(NSError **)error;

@end