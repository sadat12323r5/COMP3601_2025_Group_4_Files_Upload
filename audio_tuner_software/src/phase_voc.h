#ifndef PHASE_VOC_H
#define PHASE_VOC_H

#include <stdint.h>

// Structure to hold audio data
typedef struct {
    float* data;
    int length;
    int sample_rate;
} AudioBuffer;

/**
 * Apply phase vocoder pitch shifting to an audio buffer
 * @param input      Input audio buffer
 * @param pitch_ratio Pitch shift ratio (1.0 = no change, 1.2 = 20% higher, 0.8 = 20% lower)
 * @return           New AudioBuffer with pitch-shifted audio (must be freed by caller)
 */
AudioBuffer* phase_vocoder_pitch_shift(AudioBuffer* input, float pitch_ratio);

/**
 * Read a WAV file into an AudioBuffer
 * @param filename   Path to WAV file
 * @return           AudioBuffer with loaded audio data (must be freed by caller)
 */
AudioBuffer* read_wav_file(const char* filename);

/**
 * Write an AudioBuffer to a WAV file
 * @param filename   Output WAV file path
 * @param audio      AudioBuffer to write
 * @return           0 on success, -1 on error
 */
int write_wav_file(const char* filename, AudioBuffer* audio);

/**
 * Free an AudioBuffer and its data
 * @param audio      AudioBuffer to free
 */
static inline void free_audio_buffer(AudioBuffer* audio) {
    if (audio) {
        if (audio->data) {
            free(audio->data);
        }
        free(audio);
    }
}

#endif // PHASE_VOC_H
