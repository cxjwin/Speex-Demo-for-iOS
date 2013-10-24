//
//  MediaCodec.m
//  TEST_Speex_001
//
//  Created by cxjwin on 13-6-28.
//  Copyright (c) 2013年 caixuejun. All rights reserved.
//

#import <sys/stat.h>
#import "SpeexManager.h"

@implementation SpeexManager 
{
    CFTimeInterval beginTime;
}

#pragma mark AudioSession listeners
void InterruptionListener(void * inClientData, UInt32 inInterruptionState)
{
    SpeexManager *intercom = (__bridge SpeexManager *)inClientData;
    if (inInterruptionState == kAudioSessionBeginInterruption) {
		if ([intercom isRecording]) {
			[intercom stopRecording:nil];
		}
        if ([intercom isPlaying]) {
			[intercom stopPlaying:nil];
		}
	} else if (inInterruptionState == kAudioSessionEndInterruption) {
        // do nothing
	}
}

#pragma mark AudioSession Property listeners
void AudioRouteChangePropertyListener(void *inClientData, AudioSessionPropertyID inID, UInt32 inDataSize, const void *inData) 
{
    if (inID != kAudioSessionProperty_AudioRouteChange) {
        return;
    }
    
    SpeexManager *intercom = (__bridge SpeexManager *)inClientData;
    CFDictionaryRef routeDictionary = (CFDictionaryRef)inData;
    CFNumberRef reason =
    (CFNumberRef)CFDictionaryGetValue(routeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_Reason));
    SInt32 reasonVal;
    CFNumberGetValue(reason, kCFNumberSInt32Type, &reasonVal);
    
    if (reasonVal == kAudioSessionRouteChangeReason_NewDeviceAvailable ||
        reasonVal == kAudioSessionRouteChangeReason_OldDeviceUnavailable) {
        if ([intercom.delegate respondsToSelector:@selector(audioSessionRouteHasChanged:)]) {
            [intercom.delegate audioSessionRouteHasChanged:reasonVal];
        }
    }
}

#pragma mark - init

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OSStatus status = AudioSessionInitialize(CFRunLoopGetCurrent(),
                                                 kCFRunLoopCommonModes,
                                                 &InterruptionListener,
                                                 (__bridge void *)(self));
        if (status) {
            NSLog(@"couldn't init audio session interruption listener");
        }
    });
}

- (id)init {
    self = [super init];
    if (self) {
        [self registerForAudioQueueNotifications];
        [self registerForBackgroundNotifications];
        
        _minRecordingTime = kTimeLimitShort;
        _maxRecordingTime = kTimeLimitLong;
        
        OSStatus status = 0;
        UInt32 category = kAudioSessionCategory_PlayAndRecord;
        status = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                                         sizeof(category),
                                         &category);
        if (status) {
            NSLog(@"couldn't set audio session category");
            return nil;
        }
        
        status = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange,
                                                 AudioRouteChangePropertyListener,
                                                 (__bridge void *)(self));
        if (status) {
            NSLog(@"couldn't add audio session prop listener");
            return nil;
        }
        
        Float32 preferredBufferSize = 0.005;
        status = AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration,
                                         sizeof(preferredBufferSize),
                                         &preferredBufferSize);
        if (status) {
            NSLog(@"couldn't set i/o buffer duration");
            return nil;
        }
        
        self.speexRecorder = [[SpeexRecorder alloc] init];
        self.speexPlayer = [[SpeexPlayer alloc] init];
    }
    return self;
}

- (void)dealloc 
{
    [self unregisterForAudioQueueNotifications];
    [self unregisterForBackgroundNotifications];
}

#pragma mark - recorder functions
- (UInt32)inputIsAvailable 
{
    UInt32 _isAvailable;
    UInt32 size = sizeof(_isAvailable);
    AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable,
                            &size,
                            &_isAvailable);
    return _isAvailable;
}

- (double)calculatePlayTime:(NSString *)filePath error:(NSError **)error 
{
    if (filePath) {
        const char *speexFileName = [filePath cStringUsingEncoding:NSUTF8StringEncoding];
        char magic[SPEEX_HEADER_STRING_LENGTH] = "Speex   ";
        FILE *filePoint = fopen(speexFileName, "rb");
        
        bool isSpeex = true;
        if (filePoint == NULL) {
#ifdef DEBUG
            fprintf(stderr, "Speex文件打开失败.\n");
#endif
        }
        
        SpeexHeader speexHeader;
        fread(&speexHeader, sizeof(SpeexHeader), 1, filePoint);
        if (ferror(filePoint)) {
            isSpeex = FALSE;
#ifdef DEBUG
            fprintf(stderr, "Speex文件头读取失败.\n");
#endif
            clearerr(filePoint);
            fclose(filePoint);
        }
        
        if (strncmp(speexHeader.speex_string, magic, SPEEX_HEADER_STRING_LENGTH)) {
            isSpeex = FALSE;
#ifdef DEBUG
            fprintf(stderr, "Speex文件头不匹配.\n");
#endif
            fclose(filePoint);
        }
        
        if (isSpeex) {
            int nbytes;
            fread(&nbytes, sizeof(int), 1, filePoint);
            size_t frame_size = nbytes + sizeof(int);
            
            struct stat st;
            lstat(speexFileName, &st);
            double time = (double)(st.st_size - sizeof(SpeexHeader)) / frame_size * 0.02; // 20msec
            return time;
        }
    }
    return 0;
}

- (BOOL)startRecordingWithSpeexFilePath:(NSString *)filePath error:(NSError **)error 
{
    OSStatus status = AudioSessionSetActive(true);
    if (status) {
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"couldn't set audio session active"
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:kSpeexErrorDomain
                                         code:status
                                     userInfo:userInfo];
        }
        return NO;
    }
    BOOL success = [self.speexRecorder startRecordingWithSpeexFilePath:filePath error:error];
    if (success) {
        self.recorderFilePath = filePath;
    }
    return success;
}

- (void)refreshMeter 
{
    float averagePower = [self.speexRecorder averagePower];
    if ([_delegate respondsToSelector:@selector(recordingStatusWithMeter:)]) {
        [_delegate recordingStatusWithMeter:averagePower];
    }
}

- (void)refreshTime 
{
    float currentTime = [self.speexRecorder currentTime];
    if ([_delegate respondsToSelector:@selector(recordingStatusWithCurrentTime:)]) {
        [_delegate recordingStatusWithCurrentTime:currentTime];
    }
}

- (BOOL)stopRecording:(NSError **)error
{
    return [self.speexRecorder stopRecording:error];
}

- (BOOL)isRecording 
{
    return self.speexRecorder.isRecording;
}

- (void)deleteFile:(NSString *)filePath 
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    BOOL sucess = [fileManager removeItemAtPath:filePath
                                          error:&error];
    if (sucess == NO) {
        NSLog(@"Err:%@", [error localizedDescription]);
    }
}

#pragma mark - player functions
- (BOOL)startPlayingWithSpeexFilePath:(NSString *)filePath error:(NSError **)error 
{
    OSStatus status = AudioSessionSetActive(true);
    if (status) {
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"couldn't set audio session active"
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:kSpeexErrorDomain
                                         code:status
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    BOOL success = [self.speexPlayer startPlayingWithSpeexFilePath:filePath error:error];
    if (success) {
        self.playerFilePath = filePath;
    }
    return success;
}

- (BOOL)stopPlaying:(NSError **)error 
{
    return [self.speexPlayer stopPlaying:error];
}

- (BOOL)isPlaying
{
    return self.speexPlayer.isPlaying;
}

#pragma mark - playback queue notifications
- (void)registerForAudioQueueNotifications 
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(inputAudioQueueStarted)
                                                 name:kInputAudioQueueStarted
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(inputAudioQueueStopped)
                                                 name:kInputAudioQueueStopped
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(outputAudioQueueStarted)
     
                                                 name:kOutputAudioQueueStarted
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(outputAudioQueueStopped)
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

- (void)outputAudioQueueStarted 
{
    // 播放开始...
}

- (void)outputAudioQueueStopped 
{
    OSStatus status = AudioSessionSetActive(false);
    if (status) {
        NSLog(@"couldn't set audio session active");
    }
}

- (void)inputAudioQueueStarted 
{
    beginTime = CFAbsoluteTimeGetCurrent();
    
    self.timerMeter =
    [NSTimer scheduledTimerWithTimeInterval:kTimeInterval1
                                     target:self
                                   selector:@selector(refreshMeter)
                                   userInfo:nil
                                    repeats:YES];
    
    self.timerCurrentTime =
    [NSTimer scheduledTimerWithTimeInterval:kTimeInterval2
                                     target:self
                                   selector:@selector(refreshTime)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)inputAudioQueueStopped 
{
    CFTimeInterval deltaTime = CFAbsoluteTimeGetCurrent() - beginTime;
    
    if (deltaTime < _minRecordingTime) {
        NSLog(@"录音时间太短...");
        if ([_delegate respondsToSelector:@selector(recordingTimeTooShort)]) {
            [_delegate recordingTimeTooShort];
        }
        [self deleteFile:self.recorderFilePath];
    } else {
        if (deltaTime < _maxRecordingTime) {
            if ([_delegate respondsToSelector:@selector(recordingInTime)]) {
                [_delegate recordingInTime];
            }
        } else {
            NSLog(@"录音时间太长...");
            if ([_delegate respondsToSelector:@selector(recordingTimeTooLong)]) {
                [_delegate recordingTimeTooLong];
            }
        }
        if ([_delegate respondsToSelector:@selector(didFinishedRecording:)]) {
            [_delegate didFinishedRecording:self.recorderFilePath];
        }
    }
    
    [self.timerMeter invalidate];
    [self.timerCurrentTime invalidate];
    
    OSStatus status = AudioSessionSetActive(FALSE);
    if (status) {
        NSLog(@"couldn't set audio session active");
    }
}

#pragma mark - background notifications
- (void)registerForBackgroundNotifications 
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(resignActive)
												 name:UIApplicationWillResignActiveNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(enterForeground)
												 name:UIApplicationWillEnterForegroundNotification
											   object:nil];
}

- (void)unregisterForBackgroundNotifications 
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationWillResignActiveNotification
                                                  object:nil];
    
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationWillEnterForegroundNotification
                                                  object:nil];
}

- (void)resignActive 
{
    if ([self isRecording]) {
        [self stopRecording:nil];
    }
    if ([self isPlaying]) {
        [self stopPlaying:nil];
    }
}

- (void)enterForeground
{
	
}

@end
