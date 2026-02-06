// FFmpeg-iOS: Swift package to use FFmpeg in your iOS apps
// Copyright (C) 2023  Changbeom Ahn
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; either
// version 2.1 of the License, or (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

#import <Foundation/Foundation.h>
#import "Hook.h"
#include <pthread.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define HOOK0 1973

jmp_buf j;

typedef struct {
    char *data;
    size_t length;
    size_t capacity;
} HookBuffer;

static pthread_mutex_t gCaptureMutex = PTHREAD_MUTEX_INITIALIZER;

static void HookBufferInit(HookBuffer *buffer) {
    buffer->data = NULL;
    buffer->length = 0;
    buffer->capacity = 0;
}

static void HookBufferFree(HookBuffer *buffer) {
    free(buffer->data);
    buffer->data = NULL;
    buffer->length = 0;
    buffer->capacity = 0;
}

static int HookBufferReserve(HookBuffer *buffer, size_t capacity) {
    if (capacity <= buffer->capacity) {
        return 1;
    }
    size_t newCapacity = buffer->capacity ? buffer->capacity : 1024;
    while (newCapacity < capacity) {
        if (newCapacity > (SIZE_MAX / 2)) {
            return 0;
        }
        newCapacity *= 2;
    }
    char *newData = realloc(buffer->data, newCapacity);
    if (!newData) {
        return 0;
    }
    buffer->data = newData;
    buffer->capacity = newCapacity;
    return 1;
}

static void HookBufferAppend(HookBuffer *buffer, const char *text, size_t length) {
    if (!text || !length) {
        return;
    }
    size_t required = buffer->length + length + 1;
    if (!HookBufferReserve(buffer, required)) {
        return;
    }
    memcpy(buffer->data + buffer->length, text, length);
    buffer->length += length;
    buffer->data[buffer->length] = '\0';
}

static char *HookBufferCopyCString(const HookBuffer *buffer) {
    if (!buffer->length) {
        return NULL;
    }
    char *copy = malloc(buffer->length + 1);
    if (!copy) {
        return NULL;
    }
    memcpy(copy, buffer->data, buffer->length);
    copy[buffer->length] = '\0';
    return copy;
}

static char *HookReadAllFromFile(FILE *file) {
    if (!file) {
        return NULL;
    }
    fflush(file);
    if (fseek(file, 0, SEEK_SET) != 0) {
        return NULL;
    }

    HookBuffer buffer;
    HookBufferInit(&buffer);
    char chunk[4096];
    size_t bytesRead = 0;
    while ((bytesRead = fread(chunk, 1, sizeof(chunk), file)) > 0) {
        HookBufferAppend(&buffer, chunk, bytesRead);
    }

    char *result = HookBufferCopyCString(&buffer);
    HookBufferFree(&buffer);
    return result;
}

static void resetFFmpeg(void) {
    // FIXME: replace with #include <ffmpeg.h>
    extern int nb_input_files;
    extern int nb_output_files;
    extern int nb_filtergraphs;

    nb_input_files = 0;
    nb_output_files = 0;
    nb_filtergraphs = 0;
}

static void resetFFprobe() {
    // FIXME: ...
}

void FFmpeg_exit(int code) {
    NSLog(@"%s=%d, will longjmp", __func__, code);
    longjmp(j, code ?: HOOK0);
}

int HookMain(int argc, char **argv, int (*realMain)(int, char**), void (*reset)()) {
    int ret = setjmp(j);
    NSLog(@"%s: setjmp=%d", __func__, ret);
    if (ret) {
        reset();
        return ret == HOOK0 ? 0 : ret;
    }

    ret = realMain(argc, argv);
    NSLog(@"%s: realMain=%d", __func__, ret);
    reset();
    return ret;
}

static int HookMainCapture(int argc, char **argv, int (*realMain)(int, char**), void (*reset)(),
                           char **capturedStdout, char **capturedStderr) {
    if (capturedStdout) {
        *capturedStdout = NULL;
    }
    if (capturedStderr) {
        *capturedStderr = NULL;
    }

    pthread_mutex_lock(&gCaptureMutex);

    int savedStdout = dup(STDOUT_FILENO);
    int savedStderr = dup(STDERR_FILENO);
    FILE *stdoutFile = tmpfile();
    FILE *stderrFile = tmpfile();
    if (savedStdout >= 0 && stdoutFile) {
        dup2(fileno(stdoutFile), STDOUT_FILENO);
    }
    if (savedStderr >= 0 && stderrFile) {
        dup2(fileno(stderrFile), STDERR_FILENO);
    }

    int ret = HookMain(argc, argv, realMain, reset);

    fflush(stdout);
    fflush(stderr);
    if (savedStdout >= 0) {
        dup2(savedStdout, STDOUT_FILENO);
        close(savedStdout);
    }
    if (savedStderr >= 0) {
        dup2(savedStderr, STDERR_FILENO);
        close(savedStderr);
    }

    if (capturedStdout && stdoutFile) {
        *capturedStdout = HookReadAllFromFile(stdoutFile);
    }
    if (capturedStderr && stderrFile) {
        *capturedStderr = HookReadAllFromFile(stderrFile);
    }
    if (stdoutFile) {
        fclose(stdoutFile);
    }
    if (stderrFile) {
        fclose(stderrFile);
    }

    pthread_mutex_unlock(&gCaptureMutex);
    return ret;
}

int HookFFmpeg(int argc, char **argv) {
    extern int FFmpeg_main(int, char**);
    return HookMain(argc, argv, FFmpeg_main, resetFFmpeg);
}

int HookFFprobe(int argc, char **argv) {
    extern int FFprobe_main(int, char**);
    return HookMain(argc, argv, FFprobe_main, resetFFprobe);
}

int HookFFmpegCapture(int argc, char **argv, char **capturedStdout, char **capturedStderr) {
    extern int FFmpeg_main(int, char**);
    return HookMainCapture(argc, argv, FFmpeg_main, resetFFmpeg, capturedStdout, capturedStderr);
}

int HookFFprobeCapture(int argc, char **argv, char **capturedStdout, char **capturedStderr) {
    extern int FFprobe_main(int, char**);
    return HookMainCapture(argc, argv, FFprobe_main, resetFFprobe, capturedStdout, capturedStderr);
}

void HookFreeCString(char *cstring) {
    free(cstring);
}
