//
//  SpeexRecorder.m
//  TEST_Speex_001
//
//  Created by cxjwin on 13-6-28.
//  Copyright (c) 2013年 caixuejun. All rights reserved.
//

#import "SpeexRecorder.h"
// Sampling rate values of 8000, 16000 or 32000 Hz MUST be used
#define kSamplesPerSecond 8000
// The encoding and decoding algorithm can change the bit rate at any 20 msec frame boundary
#define kFrameBoundary 20 // 20msec
#define kPcmFrameSize 160 // 8000(8khz) * (1000msec / 20msec)hz = 160
#define kMaxNbBytes 200

#define kMaxDB 45

@implementation SpeexRecorder 

#pragma mark - static functions
static inline void ReadPCMFrameData(AudioSampleType *speech, char *fpwave, UInt32 len) 
{
    UInt32 shortLen = (UInt32)len / 2;
	AudioSampleType pcmFrame_16b1[shortLen];
    memcpy(pcmFrame_16b1, fpwave, len);
    for(int x = 0; x < shortLen; x++) {
        speech[x] = pcmFrame_16b1[x+0];
    }
}

static void HandleInputBuffer(void *inUserData,
                              AudioQueueRef inAQ,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumberPacketDescriptions,
                              const AudioStreamPacketDescription *inPacketDescs) 
{
    SpeexRecorder *recorder = (__bridge SpeexRecorder *)inUserData;
    
    if (inNumberPacketDescriptions > 0) {
        
        char *data = inBuffer->mAudioData;
        char *oldBuf = inBuffer->mAudioData;
        UInt32 maxLen = inBuffer->mAudioDataByteSize;
        
        AudioSampleType speech[kPcmFrameSize];
        float input[kPcmFrameSize];
        char speexFrame[kMaxNbBytes];
        
        SpeexBits bits;
        speex_bits_init(&bits);
        for (; ; ) {
            // read one pcm frame
            if (data - oldBuf >= maxLen) {
                break;
            }
            
            int len = maxLen - (data - oldBuf);
            len = (len < 320 ? len : 320);
            
            ReadPCMFrameData(speech, data, len);
            
            for (int i = 0; i < kPcmFrameSize; i++) {
                input[i] = speech[i];
            }
            
            data += len;
            
            speex_bits_reset(&bits);
            speex_encode(recorder->encoder, input, &bits);
            
            int byte_counter = speex_bits_write(&bits, speexFrame, kMaxNbBytes);
            
            fwrite(&byte_counter, sizeof(int), 1, recorder->fp);
            if (ferror(recorder->fp)) {
                speex_bits_destroy(&bits);
                clearerr(recorder->fp);
                break;
            }
            
            fwrite(speexFrame, sizeof(char), byte_counter, recorder->fp);
            if(ferror(recorder->fp)) {
                speex_bits_destroy(&bits);
                clearerr(recorder->fp);
                break;
            }
        }
        speex_bits_destroy(&bits);
        
        if (recorder.isRecording) {
            AudioQueueEnqueueBuffer(recorder->queue, inBuffer, 0, NULL);
        }
    }
}

static void RecorderIsRunningProc(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID) 
{
    SpeexRecorder *recorder = (__bridge SpeexRecorder *)inUserData;
    UInt32 isRecording;
    UInt32 size = sizeof(isRecording);
    OSStatus result = AudioQueueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &isRecording, &size);
    if (result == noErr) {
        recorder.isRecording = isRecording;
        if (isRecording) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kInputAudioQueueStarted object:nil];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:kInputAudioQueueStopped object:nil];
        }
    }
}

- (id)init 
{
    self = [super init];
    if (self) {
        // init encoder
        int tmp = 1;// bps?
        encoder = speex_encoder_init(&speex_nb_mode);
        speex_encoder_ctl(encoder, SPEEX_SET_QUALITY, &tmp);
        
        preprocessState = speex_preprocess_state_init(kPcmFrameSize, kSamplesPerSecond);
        
        int denoise = 1;
        int noiseSuppress = -10;
        speex_preprocess_ctl(preprocessState, SPEEX_PREPROCESS_SET_DENOISE, &denoise);// 降噪
        speex_preprocess_ctl(preprocessState, SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &noiseSuppress);// 噪音分贝数
        
        int agc = 1;
        int level = 24000;
        //actually default is 8000(0,32768),here make it louder for voice is not loudy enough by default.
        speex_preprocess_ctl(preprocessState, SPEEX_PREPROCESS_SET_AGC, &agc);// 增益
        speex_preprocess_ctl(preprocessState, SPEEX_PREPROCESS_SET_AGC_LEVEL,&level);// 增益后的值
        
        // init audio queue
        [self initRecorder];
    }
    return self;
}

- (void)dealloc 
{
    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueFreeBuffer(queue, buffers[i]);
    }
    AudioQueueDispose(queue, TRUE), queue = NULL;
    speex_encoder_destroy(encoder), encoder = NULL;
    speex_preprocess_state_destroy(preprocessState);
    if (fp) {
        fclose(fp), fp = NULL;
    }
}

- (void)setupAudioFormat:(AudioStreamBasicDescription *)format 
{
    memset(format, 0, sizeof(AudioStreamBasicDescription));
    format->mSampleRate = kSamplesPerSecond;
    format->mFormatID = kAudioFormatLinearPCM;
    // uses the standard flags
    format->mFormatFlags = kAudioFormatFlagsCanonical;
    // mono
    format->mChannelsPerFrame = 1;
    // 1byte = 8bit
    // kAudioFormatFlagsCanonical match the AudioSampleType type
    format->mBitsPerChannel = 8 * sizeof(AudioSampleType);
    format->mFramesPerPacket = 1;
    format->mBytesPerFrame = sizeof(AudioSampleType) * format->mChannelsPerFrame;
    format->mBytesPerPacket = format->mBytesPerFrame * format->mFramesPerPacket;
}

- (void)initRecorder 
{
    [self setupAudioFormat:&dataFormat];
    
    OSStatus status = noErr;
    status = 
    AudioQueueNewInput(&dataFormat, HandleInputBuffer, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &queue);
    
    UInt32 enableMetering = 1;
    status = AudioQueueSetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &enableMetering, sizeof(enableMetering));
    
    status = AudioQueueAddPropertyListener(queue, kAudioQueueProperty_IsRunning, RecorderIsRunningProc, (__bridge void *)(self));
    
    UInt32 bufferByteSize =
    (UInt32)dataFormat.mSampleRate * dataFormat.mBytesPerPacket * kBufferDurationSeconds;
    for(int i = 0; i < kNumberBuffers; i++) {
        status = AudioQueueAllocateBuffer(queue, bufferByteSize, &buffers[i]);
    }
}

- (float)currentTime 
{
    AudioTimeStamp outTimeStamp;
    OSStatus status = AudioQueueGetCurrentTime(queue, NULL, &outTimeStamp, NULL);
    if (status) {
        printf("Error: Could not retrieve current time\n");
        return 0.0f;
    }
    return outTimeStamp.mSampleTime / kSamplesPerSecond;
}

- (float)averagePower 
{
    AudioQueueLevelMeterState state[1];
    UInt32 statesize = sizeof(state);
    OSStatus status = AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentLevelMeterDB, &state, &statesize);
    if (status) {
        printf("Error retrieving meter data\n");
        return 0.0f;
    }
    float averagePower = (kMaxDB + 10 + state[0].mAveragePower) / kMaxDB;
    return (averagePower > 0 ? averagePower : 0);
}

- (float)peakPower 
{
    AudioQueueLevelMeterState state[1];
    UInt32 statesize = sizeof(state);
    OSStatus status = AudioQueueGetProperty(queue,
                                            kAudioQueueProperty_CurrentLevelMeterDB,
                                            &state,
                                            &statesize);
    if (status) {printf("Error retrieving meter data\n"); return 0.0f;}
    float peakPower = (kMaxDB + 10 + state[0].mPeakPower) / kMaxDB;
    return (peakPower > 0 ? peakPower : 0);
}

- (BOOL)startRecordingWithSpeexFilePath:(NSString *)amrFilePath error:(NSError **)error
{
    if ([self stopRecording:error] == NO) {
        return NO;
    }
    
    const char *path = [amrFilePath cStringUsingEncoding:NSUTF8StringEncoding];
    fp = fopen(path, "wb");
    if (fp == NULL) {
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"couldn't open file"
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:kSpeexErrorDomain
                                         code:SpeexFileError
                                     userInfo:userInfo];
        }
		return NO;
	}
    
    SpeexHeader speexHeader;
    speex_init_header(&speexHeader, kSamplesPerSecond, 1, &speex_nb_mode);
    size_t size = fwrite(&speexHeader, 1, sizeof(SpeexHeader), fp);
    if (size < sizeof(SpeexHeader)) {
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"couldn't write file"
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:kSpeexErrorDomain
                                         code:SpeexFileError
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    for (int i = 0; i < kNumberBuffers; i++) {
        OSStatus status = AudioQueueEnqueueBuffer(queue, buffers[i], 0, NULL);
        if (status) {
            if (error) {
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"couldn't enqueue buffer"
                                                                     forKey:NSLocalizedDescriptionKey];
                *error = [NSError errorWithDomain:kSpeexErrorDomain
                                             code:status
                                         userInfo:userInfo];
            }
            return NO;
        }
    }
    
    self.isRecording = YES;
    OSStatus status = AudioQueueStart(queue, NULL);
    if (status) {
        self.isRecording = NO;
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"couldn't start audio queue"
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:kSpeexErrorDomain
                                         code:status
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)stopRecording:(NSError **)error
{
    OSStatus status = noErr;
    if (self.isRecording) {
        status = AudioQueueStop(queue, TRUE);
        if (status) {
            printf("Could not stop Audio queue\n");
        }
                
        if (fp) {
            fclose(fp), fp = NULL;
        }
    }
    self.isRecording = NO;
    
    return (status == noErr);
}

@end
