/*
 * wav_pitch_detection.c - Complete WAV file pitch detection
 *
 * This provides a simple interface to detect pitch from a WAV file
 */

#include "Yin.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

// WAV file header structures
typedef struct {
    char riff[4];              // "RIFF"
    uint32_t fileSize;         // File size - 8
    char wave[4];              // "WAVE"
    char fmt[4];               // "fmt "
    uint32_t fmtSize;          // Size of fmt chunk
    uint16_t audioFormat;      // Audio format (1 = PCM)
    uint16_t numChannels;      // Number of channels
    uint32_t sampleRate;       // Sample rate
    uint32_t byteRate;         // Byte rate
    uint16_t blockAlign;       // Block align
    uint16_t bitsPerSample;    // Bits per sample
} WavHeader;

typedef struct {
    char chunkId[4];           // "data"
    uint32_t chunkSize;        // Size of data
} DataChunk;

// Result structure for pitch detection
typedef struct {
    float pitch;               // Detected pitch in Hz (-1 if not detected)
    float confidence;          // Confidence level (0.0 to 1.0)
    int sampleRate;            // Sample rate of the audio
    int numSamples;            // Number of samples analyzed
    int bufferSize;            // Buffer size used for analysis
    int actualStartSample;     // Actual start sample used (after auto-detection)
} PitchResult;

/**
 * Find the first non-zero sample in a WAV file
 *
 * @param filename      Path to the WAV file
 * @param threshold     Minimum absolute value to consider as non-zero (default: 10)
 * @param maxSearch     Maximum number of samples to search (0 = search all)
 * @return              Index of first non-zero sample, or -1 on error
 */
int findAudioStart(const char* filename, int threshold, int maxSearch) {
    FILE* wavFile = fopen(filename, "rb");
    if (!wavFile) {
        return -1;
    }

    // Read WAV header
    WavHeader header;
    fread(&header, sizeof(WavHeader), 1, wavFile);

    // Find data chunk
    DataChunk dataChunk;
    while (fread(&dataChunk, sizeof(DataChunk), 1, wavFile) == 1) {
        if (strncmp(dataChunk.chunkId, "data", 4) == 0) {
            break;
        }
        fseek(wavFile, dataChunk.chunkSize, SEEK_CUR);
    }

    int bytesPerSample = header.bitsPerSample / 8;
    int totalSamples = dataChunk.chunkSize / (header.numChannels * bytesPerSample);

    if (maxSearch == 0 || maxSearch > totalSamples) {
        maxSearch = totalSamples;
    }

    // Search for first non-zero sample
    for (int i = 0; i < maxSearch; i++) {
        int16_t sample = 0;

        if (header.bitsPerSample == 16) {
            fread(&sample, sizeof(int16_t), 1, wavFile);
            if (header.numChannels > 1) {
                fseek(wavFile, (header.numChannels - 1) * sizeof(int16_t), SEEK_CUR);
            }
        } else if (header.bitsPerSample == 8) {
            uint8_t sample8;
            fread(&sample8, sizeof(uint8_t), 1, wavFile);
            sample = (int16_t)(sample8 - 128) * 256;
            if (header.numChannels > 1) {
                fseek(wavFile, header.numChannels - 1, SEEK_CUR);
            }
        }

        // Check if sample exceeds threshold
        if (abs(sample) > threshold) {
            fclose(wavFile);
            return i;
        }
    }

    fclose(wavFile);
    return -1; // No non-zero sample found
}

/**
 * Detect pitch from a WAV file
 *
 * @param filename      Path to the WAV file
 * @param startSample   Which sample to start analysis from (-1 = auto-detect, 0 = beginning)
 * @param numSamples    How many samples to analyze (0 = auto-determine optimal size)
 * @param threshold     Detection threshold (0.05 = strict, 0.15 = balanced, 0.30 = lenient)
 * @param result        Pointer to PitchResult structure to store results
 * @return              0 on success, -1 on error
 */
int detectPitchFromWav(const char* filename, int startSample, int numSamples,
                       float threshold, PitchResult* result) {

    // Initialize result
    result->pitch = -1;
    result->confidence = 0;
    result->sampleRate = 0;
    result->numSamples = 0;
    result->bufferSize = 0;
    result->actualStartSample = 0;

    // Track if we used auto-detect
    int usedAutoDetect = 0;
    int originalStartSample = startSample;

    // Auto-detect start position if startSample is -1
    if (startSample == -1) {
        usedAutoDetect = 1;
        printf("Auto-detecting audio start position...\n");
        startSample = findAudioStart(filename, 5, 100000); // Search first 100k samples
        if (startSample == -1) {
            fprintf(stderr, "Warning: Could not find audio start, using sample 0\n");
            startSample = 0;
        } else {
            printf("Audio detected starting at sample %d\n", startSample);
        }
    }
    result->actualStartSample = startSample;

    // Open WAV file
    FILE* wavFile = fopen(filename, "rb");
    if (!wavFile) {
        fprintf(stderr, "Error: Could not open file %s\n", filename);
        return -1;
    }

    // Read WAV header
    WavHeader header;
    if (fread(&header, sizeof(WavHeader), 1, wavFile) != 1) {
        fprintf(stderr, "Error: Failed to read WAV header\n");
        fclose(wavFile);
        return -1;
    }

    // Verify it's a valid WAV file
    if (strncmp(header.riff, "RIFF", 4) != 0 || strncmp(header.wave, "WAVE", 4) != 0) {
        fprintf(stderr, "Error: Not a valid WAV file\n");
        fclose(wavFile);
        return -1;
    }

    if (header.audioFormat != 1) {
        fprintf(stderr, "Error: Only PCM format is supported\n");
        fclose(wavFile);
        return -1;
    }

    result->sampleRate = header.sampleRate;

    // Find data chunk
    DataChunk dataChunk;
    while (fread(&dataChunk, sizeof(DataChunk), 1, wavFile) == 1) {
        if (strncmp(dataChunk.chunkId, "data", 4) == 0) {
            break;
        }
        // Skip this chunk
        fseek(wavFile, dataChunk.chunkSize, SEEK_CUR);
    }

    int bytesPerSample = header.bitsPerSample / 8;
    int totalSamples = dataChunk.chunkSize / (header.numChannels * bytesPerSample);

    // Auto-determine optimal buffer size if numSamples is 0
    if (numSamples == 0) {
        // Default: 2048 samples or what's available
        numSamples = 2048;
        if (startSample + numSamples > totalSamples) {
            numSamples = totalSamples - startSample;
        }
    }

    // Validate parameters
    if (startSample < 0 || startSample >= totalSamples) {
        fprintf(stderr, "Error: startSample out of range\n");
        fclose(wavFile);
        return -1;
    }

    if (startSample + numSamples > totalSamples) {
        numSamples = totalSamples - startSample;
        fprintf(stderr, "Warning: Adjusting numSamples to %d (end of file)\n", numSamples);
    }

    result->numSamples = numSamples;
    result->bufferSize = numSamples;

    // Allocate audio buffer
    int16_t* audioBuffer = (int16_t*)malloc(numSamples * sizeof(int16_t));
    if (!audioBuffer) {
        fprintf(stderr, "Error: Memory allocation failed\n");
        fclose(wavFile);
        return -1;
    }

    // Seek to start position
    int bytesPerFrame = header.numChannels * bytesPerSample;
    fseek(wavFile, startSample * bytesPerFrame, SEEK_CUR);

    // Read audio data into buffer
    for (int i = 0; i < numSamples; i++) {
        int16_t sample = 0;

        if (header.bitsPerSample == 16) {
            // Read 16-bit sample
            if (fread(&sample, sizeof(int16_t), 1, wavFile) != 1) {
                fprintf(stderr, "Error: Failed to read audio data\n");
                free(audioBuffer);
                fclose(wavFile);
                return -1;
            }

            // Skip remaining channels if stereo
            if (header.numChannels > 1) {
                fseek(wavFile, (header.numChannels - 1) * sizeof(int16_t), SEEK_CUR);
            }
        } else if (header.bitsPerSample == 8) {
            uint8_t sample8;
            if (fread(&sample8, sizeof(uint8_t), 1, wavFile) != 1) {
                fprintf(stderr, "Error: Failed to read audio data\n");
                free(audioBuffer);
                fclose(wavFile);
                return -1;
            }
            sample = (int16_t)(sample8 - 128) * 256;

            // Skip remaining channels if stereo
            if (header.numChannels > 1) {
                fseek(wavFile, header.numChannels - 1, SEEK_CUR);
            }
        } else {
            fprintf(stderr, "Error: Unsupported bits per sample: %d\n", header.bitsPerSample);
            free(audioBuffer);
            fclose(wavFile);
            return -1;
        }

        audioBuffer[i] = sample;
    }

    fclose(wavFile);

    // Initialize Yin for pitch detection
    Yin yin;
    Yin_init(&yin, numSamples, threshold);

    // Detect pitch
    float pitch = Yin_getPitch(&yin, audioBuffer);

    result->pitch = pitch;
    result->confidence = Yin_getProbability(&yin);

    // Cleanup
    free(yin.yinBuffer);
    free(audioBuffer);

    // If auto-detect was used and no pitch was detected, retry with sample 20000
    if (usedAutoDetect && pitch <= 0 && originalStartSample == -1) {
        printf("\nNo pitch detected with auto-detected start position.\n");
        printf("Retrying with start sample 44100...\n\n");
        return detectPitchFromWav(filename, 44100, numSamples, threshold, result);
    }

    return 0;
}

/**
 * Simple wrapper function - detect pitch from WAV with default settings
 * Auto-detects where audio starts
 *
 * @param filename    Path to the WAV file
 * @param result      Pointer to PitchResult structure
 * @return            0 on success, -1 on error
 */
int detectPitchSimple(const char* filename, PitchResult* result) {
    // Use defaults: auto-detect start, auto buffer size, balanced threshold
    return detectPitchFromWav(filename, -1, 2048, 0.15, result);
}

/**
 * Detect pitch from a specific time range in the WAV file
 *
 * @param filename      Path to the WAV file
 * @param startTimeMs   Start time in milliseconds
 * @param durationMs    Duration in milliseconds to analyze
 * @param threshold     Detection threshold
 * @param result        Pointer to PitchResult structure
 * @return              0 on success, -1 on error
 */
int detectPitchFromTime(const char* filename, int startTimeMs, int durationMs,
                        float threshold, PitchResult* result) {

    // First, we need to read sample rate from the file
    FILE* wavFile = fopen(filename, "rb");
    if (!wavFile) {
        fprintf(stderr, "Error: Could not open file %s\n", filename);
        return -1;
    }

    WavHeader header;
    fread(&header, sizeof(WavHeader), 1, wavFile);
    fclose(wavFile);

    // Convert time to samples
    int sampleRate = header.sampleRate;
    int startSample = (startTimeMs * sampleRate) / 1000;
    int numSamples = (durationMs * sampleRate) / 1000;

    return detectPitchFromWav(filename, startSample, numSamples, threshold, result);
}


// Example usage and testing
//int main(int argc, char* argv[]) {
//
//    if (argc < 2) {
//        printf("WAV Pitch Detection - Complete Solution\n");
//        printf("========================================\n\n");
//        printf("Usage: %s <wav_file> [start_sample] [num_samples] [threshold]\n\n", argv[0]);
//        printf("Examples:\n");
//        printf("  %s audio.wav                    # Auto-detect start, use defaults\n", argv[0]);
//        printf("  %s audio.wav -1 2048 0.15       # Auto-detect start with custom params\n", argv[0]);
//        printf("  %s audio.wav 1000 2048 0.15     # Manual start position\n\n", argv[0]);
//        printf("Parameters:\n");
//        printf("  start_sample  - Sample to start from (-1=auto-detect, 0=beginning)\n");
//        printf("  num_samples   - Buffer size (default: 2048, 0=auto)\n");
//        printf("  threshold     - Detection threshold (default: 0.15)\n");
//        return 1;
//    }
//
//    const char* filename = argv[1];
//    int startSample = (argc > 2) ? atoi(argv[2]) : -1;  // Default to auto-detect
//    int numSamples = (argc > 3) ? atoi(argv[3]) : 2048;
//    float threshold = (argc > 4) ? atof(argv[4]) : 0.15;
//
//    printf("Analyzing WAV file: %s\n", filename);
//    if (startSample == -1) {
//        printf("Parameters: start=AUTO-DETECT, samples=%d, threshold=%.2f\n\n",
//               numSamples, threshold);
//    } else {
//        printf("Parameters: start=%d, samples=%d, threshold=%.2f\n\n",
//               startSample, numSamples, threshold);
//    }
//
//    // Perform pitch detection
//    PitchResult result;
//    if (detectPitchFromWav(filename, startSample, numSamples, threshold, &result) == 0) {
//
//        printf("=== Results ===\n");
//        printf("Sample Rate:     %d Hz\n", result.sampleRate);
//        printf("Start Sample:    %d\n", result.actualStartSample);
//        printf("Samples Analyzed: %d\n", result.numSamples);
//        printf("Buffer Size:     %d\n", result.bufferSize);
//
//        if (result.pitch > 0) {
//            printf("\nPitch Detected!\n");
//            printf("  Frequency:    %.2f Hz\n", result.pitch);
//            printf("  Confidence:   %.1f%%\n", result.confidence * 100);
//
//            // Calculate musical note
//            if (result.pitch > 20 && result.pitch < 4200) {
//                const char* notes[] = {"C", "C#", "D", "D#", "E", "F",
//                                       "F#", "G", "G#", "A", "A#", "B"};
//
//                // log2(x) = log(x) / log(2)
//                float log2_val = logf(result.pitch / 440.0f) / logf(2.0f);
//                int midiNote = (int)(12 * log2_val + 69);
//                int noteIndex = midiNote % 12;
//                int octave = (midiNote / 12) - 1;
//                printf("  Musical Note: %s%d\n", notes[noteIndex], octave);
//            }
//        } else {
//            printf("\nNo pitch detected\n");
//            printf("  Try adjusting:\n");
//            printf("  - start_sample (find section with audio)\n");
//            printf("  - num_samples (larger buffer for low frequencies)\n");
//            printf("  - threshold (higher value = more lenient)\n");
//        }
//
//    } else {
//        printf("Error: Failed to analyze WAV file\n");
//        return 1;
//    }
//
//    return 0;
//}
