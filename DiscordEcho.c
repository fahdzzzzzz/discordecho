// DiscordEcho: تأثير صدى على صوت المايك داخل تطبيق (مثل ديسكورد)
// الشدة من 0 إلى 100 (0 = متوقف). تتغير من القائمة في DiscordEchoUI.m
// يعمل عبر fishhook: يستبدل AudioUnitRender ويعدّل بيانات المايك قبل ما يرسلها التطبيق.

#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <string.h>
#include "fishhook.h"

#define ECHO_DELAY_SEC 0.30f   // زمن التأخير بالثواني (ثابت)
#define MAX_FEEDBACK   0.55f   // تكرار الصدى عند شدة 100
#define MAX_MIX        0.90f   // قوة الصدى عند شدة 100

#define MAX_RATE 48000
#define MAX_BUFS 2
#define LINE_LEN (MAX_RATE * 2)

static float g_line[MAX_BUFS][LINE_LEN];
static size_t g_pos[MAX_BUFS];
static int g_cleared[MAX_BUFS];

static volatile int g_level = 50;   // 0..100

void DiscordEcho_SetLevel(int level) {
    if (level < 0) level = 0;
    if (level > 100) level = 100;
    g_level = level;
}

static AudioUnit g_unit;
static AudioStreamBasicDescription g_fmt;
static int g_have_fmt;

static OSStatus (*orig_render)(AudioUnit, AudioUnitRenderActionFlags *,
                               const AudioTimeStamp *, UInt32, UInt32,
                               AudioBufferList *);

static void process_buffer(int idx, AudioBuffer *ab) {
    int lvl = g_level;
    if (lvl == 0) {
        // متوقف: امسح بقايا الصدى مرة وحدة وخلّ الصوت يمر كما هو
        if (!g_cleared[idx]) {
            memset(g_line[idx], 0, sizeof(g_line[idx]));
            g_pos[idx] = 0;
            g_cleared[idx] = 1;
        }
        return;
    }
    g_cleared[idx] = 0;

    float k = (float)lvl / 100.0f;
    float feedback = k * MAX_FEEDBACK;
    float mix = k * MAX_MIX;

    int is_float = (g_fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    UInt32 bits = g_fmt.mBitsPerChannel;
    if (!((is_float && bits == 32) || (!is_float && bits == 16))) return;

    UInt32 bytes_per = bits / 8;
    size_t n = ab->mDataByteSize / bytes_per;
    UInt32 chans = ab->mNumberChannels ? ab->mNumberChannels : 1;

    size_t D = (size_t)(ECHO_DELAY_SEC * (float)g_fmt.mSampleRate) * chans;
    if (D < 1) D = 1;
    if (D >= LINE_LEN) D = LINE_LEN - 1;

    float *line = g_line[idx];
    size_t p = g_pos[idx];
    if (p >= D) p = 0;

    for (size_t i = 0; i < n; i++) {
        float x;
        if (is_float) x = ((float *)ab->mData)[i];
        else          x = ((int16_t *)ab->mData)[i] / 32768.0f;

        float d = line[p];
        line[p] = x + feedback * d;
        float y = x + mix * d;
        if (y > 1.0f) y = 1.0f;
        if (y < -1.0f) y = -1.0f;

        if (is_float) ((float *)ab->mData)[i] = y;
        else          ((int16_t *)ab->mData)[i] = (int16_t)(y * 32767.0f);

        if (++p >= D) p = 0;
    }
    g_pos[idx] = p;
}

static OSStatus my_render(AudioUnit unit, AudioUnitRenderActionFlags *flags,
                          const AudioTimeStamp *ts, UInt32 bus,
                          UInt32 frames, AudioBufferList *io) {
    OSStatus st = orig_render(unit, flags, ts, bus, frames, io);
    if (st != noErr || bus != 1 || io == NULL) return st;   // bus 1 = المايك

    if (unit != g_unit || !g_have_fmt) {
        UInt32 sz = sizeof(g_fmt);
        if (AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Output, 1, &g_fmt, &sz) == noErr) {
            g_unit = unit;
            g_have_fmt = 1;
        } else {
            g_have_fmt = 0;
            return st;
        }
    }

    for (UInt32 b = 0; b < io->mNumberBuffers && b < MAX_BUFS; b++) {
        if (io->mBuffers[b].mData) process_buffer((int)b, &io->mBuffers[b]);
    }
    return st;
}

__attribute__((constructor))
static void init(void) {
    struct rebinding r = { "AudioUnitRender", (void *)my_render, (void **)&orig_render };
    rebind_symbols(&r, 1);
}
