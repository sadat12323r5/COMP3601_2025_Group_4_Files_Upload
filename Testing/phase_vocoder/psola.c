#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Configuration
#define MAX_PERIOD 2048
#define MIN_PERIOD 32

// Structure to hold audio data
typedef struct {
    float* data;
    int length;
    int sample_rate;
} AudioBuffer;

// Structure for pitch marks (period boundaries)
typedef struct {
    int* positions;
    int count;
    int capacity;
} PitchMarks;

// Hanning window function
static inline float hanning(int n, int N) {
    return 0.5f * (1.0f - cosf(2.0f * M_PI * n / (N - 1)));
}

// Initialize pitch marks structure
PitchMarks* pitch_marks_create(int capacity) {
    PitchMarks* pm = (PitchMarks*)malloc(sizeof(PitchMarks));
    pm->positions = (int*)malloc(capacity * sizeof(int));
    pm->count = 0;
    pm->capacity = capacity;
    return pm;
}

void pitch_marks_free(PitchMarks* pm) {
    free(pm->positions);
    free(pm);
}

void pitch_marks_add(PitchMarks* pm, int position) {
    if (pm->count >= pm->capacity) {
        pm->capacity *= 2;
        pm->positions = (int*)realloc(pm->positions, pm->capacity * sizeof(int));
    }
    pm->positions[pm->count++] = position;
}

// Simple autocorrelation-based pitch detection
float detect_pitch_period(float* buffer, int start, int length, int sample_rate) {
    if (start + MAX_PERIOD >= length) {
        return 0.0f;
    }
    
    int search_length = (length - start < MAX_PERIOD) ? length - start : MAX_PERIOD;
    float max_corr = 0.0f;
    int best_lag = MIN_PERIOD;
    
    // Autocorrelation
    for (int lag = MIN_PERIOD; lag < search_length; lag++) {
        float corr = 0.0f;
        float energy = 0.0f;
        
        for (int i = 0; i < search_length - lag; i++) {
            corr += buffer[start + i] * buffer[start + i + lag];
            energy += buffer[start + i] * buffer[start + i];
        }
        
        if (energy > 0.0f) {
            corr /= energy;
            if (corr > max_corr) {
                max_corr = corr;
                best_lag = lag;
            }
        }
    }
    
    return (max_corr > 0.3f) ? (float)best_lag : 0.0f;
}

// Detect pitch marks throughout the signal
PitchMarks* detect_pitch_marks(AudioBuffer* audio) {
    PitchMarks* marks = pitch_marks_create(1000);
    
    int position = 0;
    marks->positions[marks->count++] = 0;
    
    while (position < audio->length) {
        float period = detect_pitch_period(audio->data, position, audio->length, audio->sample_rate);
        
        if (period > 0 && period < MAX_PERIOD) {
            position += (int)period;
        } else {
            position += 200; // Fallback
        }
        
        if (position < audio->length) {
            pitch_marks_add(marks, position);
        }
    }
    
    return marks;
}

// Extract a grain with proper windowing
void extract_grain(float* input, int input_length, int center, int grain_size, float* grain) {
    int half_size = grain_size / 2;
    
    for (int i = 0; i < grain_size; i++) {
        int pos = center - half_size + i;
        
        if (pos >= 0 && pos < input_length) {
            grain[i] = input[pos] * hanning(i, grain_size);
        } else {
            grain[i] = 0.0f;
        }
    }
}

// Overlap-add with proper bounds checking
void overlap_add(float* output, float* grain, int center, int grain_size, int output_length) {
    int half_size = grain_size / 2;
    
    for (int i = 0; i < grain_size; i++) {
        int pos = center - half_size + i;
        
        if (pos >= 0 && pos < output_length) {
            output[pos] += grain[i];
        }
    }
}

// TRUE PSOLA pitch shifting - pitch shift WITHOUT changing duration
AudioBuffer* psola_pitch_shift(AudioBuffer* input, float pitch_ratio) {
    printf("Starting PSOLA pitch shift with ratio: %.3f\n", pitch_ratio);
    
    // Clamp pitch ratio to reasonable range
    if (pitch_ratio < 0.5f) pitch_ratio = 0.5f;
    if (pitch_ratio > 2.0f) pitch_ratio = 2.0f;
    
    // 1. Detect pitch marks in input signal
    PitchMarks* input_marks = detect_pitch_marks(input);
    printf("Detected %d input pitch marks\n", input_marks->count);
    
    if (input_marks->count < 2) {
        printf("Error: Not enough pitch marks detected\n");
        pitch_marks_free(input_marks);
        return NULL;
    }
    
    // 2. Calculate periods between marks
    int* periods = (int*)malloc((input_marks->count - 1) * sizeof(int));
    int total_period = 0;
    for (int i = 0; i < input_marks->count - 1; i++) {
        periods[i] = input_marks->positions[i+1] - input_marks->positions[i];
        total_period += periods[i];
    }
    int avg_period = total_period / (input_marks->count - 1);
    
    printf("Average period: %d samples\n", avg_period);
    
    // 3. Generate OUTPUT pitch marks with modified periods
    //    Key: Output periods = Input periods / pitch_ratio
    //    This makes the output have more/fewer periods in the same time
    PitchMarks* output_marks = pitch_marks_create(input_marks->count * 2);
    output_marks->positions[output_marks->count++] = 0;
    
    int out_pos = 0;
    int in_idx = 0;
    
    while (out_pos < input->length && in_idx < input_marks->count - 1) {
        // Calculate output period (scaled by pitch ratio)
        int out_period = (int)(periods[in_idx] / pitch_ratio);
        if (out_period < 20) out_period = 20;
        
        out_pos += out_period;
        
        if (out_pos < input->length) {
            pitch_marks_add(output_marks, out_pos);
        }
        
        in_idx++;
        
        // If we run out of input marks but still have output time, reuse last period
        if (in_idx >= input_marks->count - 1 && out_pos < input->length) {
            in_idx = input_marks->count - 2;
        }
    }
    
    printf("Generated %d output pitch marks\n", output_marks->count);
    
    // 4. Create output buffer (SAME length as input - duration preserved!)
    AudioBuffer* output = (AudioBuffer*)malloc(sizeof(AudioBuffer));
    output->length = input->length;
    output->sample_rate = input->sample_rate;
    output->data = (float*)calloc(output->length, sizeof(float));
    
    // 5. Allocate grain buffer (2x average period)
    int grain_size = avg_period * 2;
    if (grain_size < 64) grain_size = 64;
    if (grain_size > 4096) grain_size = 4096;
    float* grain = (float*)malloc(grain_size * sizeof(float));
    
    printf("Using grain size: %d samples\n", grain_size);
    
    // 6. PSOLA synthesis - extract from input marks, place at output marks
    //    This is the core: we're taking periodic chunks and placing them at
    //    different intervals, which changes pitch while preserving time
    
    int grains_processed = 0;
    
    for (int i = 0; i < output_marks->count; i++) {
        int out_mark = output_marks->positions[i];
        
        // Find closest input mark to use as source
        int closest_in_mark = 0;
        int min_dist = abs(input_marks->positions[0] - out_mark);
        
        for (int j = 1; j < input_marks->count; j++) {
            int dist = abs(input_marks->positions[j] - out_mark);
            if (dist < min_dist) {
                min_dist = dist;
                closest_in_mark = j;
            }
        }
        
        int in_mark = input_marks->positions[closest_in_mark];
        
        // Safety check
        if (in_mark < 0 || in_mark >= input->length) continue;
        if (out_mark < 0 || out_mark >= output->length) continue;
        
        // Determine local grain size based on the period
        int local_grain_size = grain_size;
        if (closest_in_mark < input_marks->count - 1) {
            int local_period = input_marks->positions[closest_in_mark + 1] - in_mark;
            if (local_period > 20 && local_period < MAX_PERIOD) {
                local_grain_size = local_period * 2;
                if (local_grain_size > grain_size) local_grain_size = grain_size;
            }
        }
        
        // Extract grain from input at the input mark
        extract_grain(input->data, input->length, in_mark, local_grain_size, grain);
        
        // Place grain at the OUTPUT mark
        overlap_add(output->data, grain, out_mark, local_grain_size, output->length);
        
        grains_processed++;
    }
    
    printf("Processed %d grains\n", grains_processed);
    
    // 7. Normalize output
    float max_val = 0.0f;
    for (int i = 0; i < output->length; i++) {
        float abs_val = fabsf(output->data[i]);
        if (abs_val > max_val) max_val = abs_val;
    }
    
    if (max_val > 0.001f) {
        float norm_factor = 0.9f / max_val;
        for (int i = 0; i < output->length; i++) {
            output->data[i] *= norm_factor;
        }
    }
    
    // Cleanup
    free(grain);
    free(periods);
    pitch_marks_free(input_marks);
    pitch_marks_free(output_marks);
    
    printf("PSOLA pitch shift complete\n");
    return output;
}

// Helper function to convert frequency to pitch ratio
float freq_to_ratio(float source_freq, float target_freq) {
    return target_freq / source_freq;
}

// Helper function to convert semitones to pitch ratio
float semitones_to_ratio(float semitones) {
    return powf(2.0f, semitones / 12.0f);
}

// Simple WAV file reading (supports 16-bit PCM and 32-bit float)
AudioBuffer* read_wav_file(const char* filename) {
    FILE* f = fopen(filename, "rb");
    if (!f) {
        printf("Error: Cannot open file %s\n", filename);
        return NULL;
    }
    
    // Read RIFF header
    char riff[4];
    unsigned int file_size;
    char wave[4];
    
    fread(riff, 1, 4, f);
    fread(&file_size, 4, 1, f);
    fread(wave, 1, 4, f);
    
    if (memcmp(riff, "RIFF", 4) != 0 || memcmp(wave, "WAVE", 4) != 0) {
        printf("Error: Not a valid WAV file\n");
        fclose(f);
        return NULL;
    }
    
    // Read fmt chunk
    char fmt[4];
    unsigned int fmt_size;
    short audio_format;
    short num_channels;
    unsigned int sample_rate;
    unsigned int byte_rate;
    short block_align;
    short bits_per_sample;
    
    fread(fmt, 1, 4, f);
    fread(&fmt_size, 4, 1, f);
    fread(&audio_format, 2, 1, f);
    fread(&num_channels, 2, 1, f);
    fread(&sample_rate, 4, 1, f);
    fread(&byte_rate, 4, 1, f);
    fread(&block_align, 2, 1, f);
    fread(&bits_per_sample, 2, 1, f);
    
    // Skip any extra fmt bytes
    if (fmt_size > 16) {
        fseek(f, fmt_size - 16, SEEK_CUR);
    }
    
    // Find data chunk
    char chunk_id[4];
    unsigned int chunk_size;
    
    while (fread(chunk_id, 1, 4, f) == 4) {
        fread(&chunk_size, 4, 1, f);
        
        if (memcmp(chunk_id, "data", 4) == 0) {
            break;
        }
        // Skip this chunk
        fseek(f, chunk_size, SEEK_CUR);
    }
    
    if (memcmp(chunk_id, "data", 4) != 0) {
        printf("Error: No data chunk found\n");
        fclose(f);
        return NULL;
    }
    
    printf("WAV Info: %d Hz, %d channels, %d bits, format %d\n", 
           sample_rate, num_channels, bits_per_sample, audio_format);
    
    // Calculate number of samples
    int num_samples = chunk_size / (bits_per_sample / 8) / num_channels;
    
    // Create audio buffer
    AudioBuffer* audio = (AudioBuffer*)malloc(sizeof(AudioBuffer));
    audio->length = num_samples;
    audio->sample_rate = sample_rate;
    audio->data = (float*)malloc(num_samples * sizeof(float));
    
    // Read and convert audio data
    if (audio_format == 1 && bits_per_sample == 16) {
        // 16-bit PCM
        short* temp = (short*)malloc(chunk_size);
        fread(temp, 1, chunk_size, f);
        
        for (int i = 0; i < num_samples; i++) {
            // If stereo, mix to mono
            if (num_channels == 2) {
                audio->data[i] = (temp[i*2] + temp[i*2+1]) / 65536.0f;
            } else {
                audio->data[i] = temp[i] / 32768.0f;
            }
        }
        free(temp);
        
    } else if (audio_format == 3 && bits_per_sample == 32) {
        // 32-bit float
        float* temp = (float*)malloc(chunk_size);
        fread(temp, 1, chunk_size, f);
        
        for (int i = 0; i < num_samples; i++) {
            // If stereo, mix to mono
            if (num_channels == 2) {
                audio->data[i] = (temp[i*2] + temp[i*2+1]) / 2.0f;
            } else {
                audio->data[i] = temp[i];
            }
        }
        free(temp);
        
    } else {
        printf("Error: Unsupported audio format (format=%d, bits=%d)\n", 
               audio_format, bits_per_sample);
        free(audio->data);
        free(audio);
        fclose(f);
        return NULL;
    }
    
    fclose(f);
    return audio;
}

// Simple WAV file writing (32-bit float mono)
int write_wav_file(const char* filename, AudioBuffer* audio) {
    FILE* f = fopen(filename, "wb");
    if (!f) return -1;
    
    // WAV header
    int data_size = audio->length * sizeof(float);
    int file_size = 36 + data_size;
    
    fwrite("RIFF", 1, 4, f);
    fwrite(&file_size, 4, 1, f);
    fwrite("WAVE", 1, 4, f);
    
    // fmt chunk
    fwrite("fmt ", 1, 4, f);
    int fmt_size = 16;
    short audio_format = 3; // IEEE float
    short num_channels = 1;
    int byte_rate = audio->sample_rate * sizeof(float);
    short block_align = sizeof(float);
    short bits_per_sample = 32;
    
    fwrite(&fmt_size, 4, 1, f);
    fwrite(&audio_format, 2, 1, f);
    fwrite(&num_channels, 2, 1, f);
    fwrite(&audio->sample_rate, 4, 1, f);
    fwrite(&byte_rate, 4, 1, f);
    fwrite(&block_align, 2, 1, f);
    fwrite(&bits_per_sample, 2, 1, f);
    
    // data chunk
    fwrite("data", 1, 4, f);
    fwrite(&data_size, 4, 1, f);
    fwrite(audio->data, sizeof(float), audio->length, f);
    
    fclose(f);
    return 0;
}

// Example usage
int main(int argc, char* argv[]) {
    if (argc < 3) {
        printf("Usage: %s <input.wav> <pitch_ratio> [output.wav]\n", argv[0]);
        printf("Examples:\n");
        printf("  %s input.wav 1.5 output.wav      # Shift up 1.5x (perfect fifth)\n", argv[0]);
        printf("  %s input.wav 0.5 output.wav      # Shift down to half pitch (octave down)\n", argv[0]);
        printf("  %s input.wav 1.25992 output.wav  # Shift up 4 semitones\n", argv[0]);
        printf("\nCommon pitch ratios:\n");
        printf("  +1 semitone = 1.05946\n");
        printf("  +4 semitones = 1.25992\n");
        printf("  +7 semitones (fifth) = 1.49831\n");
        printf("  -2 semitones = 0.89090\n");
        return 1;
    }
    
    const char* input_file = argv[1];
    float pitch_ratio = atof(argv[2]);
    const char* output_file = (argc > 3) ? argv[3] : "output.wav";
    
    if (pitch_ratio <= 0.0f) {
        printf("Error: Pitch ratio must be positive\n");
        return 1;
    }
    
    // Load input WAV file
    AudioBuffer* input = read_wav_file(input_file);
    if (!input) {
        return 1;
    }
    
    printf("Loaded %d samples from %s\n", input->length, input_file);
    printf("Pitch ratio: %.5f (%.2f semitones)\n", pitch_ratio, 12.0f * log2f(pitch_ratio));
    
    // Perform pitch shift
    AudioBuffer* output = psola_pitch_shift(input, pitch_ratio);
    
    if (output) {
        // Write output
        if (write_wav_file(output_file, output) == 0) {
            printf("Output written to %s\n", output_file);
        }
        
        free(output->data);
        free(output);
    }
    
    free(input->data);
    free(input);
    
    return 0;
}