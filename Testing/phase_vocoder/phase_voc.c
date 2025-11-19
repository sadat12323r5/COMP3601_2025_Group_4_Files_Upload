#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Configuration
#define FFT_SIZE 2048
#define HOP_SIZE 512
#define OVERLAP_FACTOR (FFT_SIZE / HOP_SIZE)

// Structure to hold audio data
typedef struct {
    float* data;
    int length;
    int sample_rate;
} AudioBuffer;

// Complex number structure
typedef struct {
    float real;
    float imag;
} Complex;

// Hanning window function
static inline float hanning(int n, int N) {
    return 0.5f * (1.0f - cosf(2.0f * M_PI * n / (N - 1)));
}

// Simple FFT implementation (Cooley-Tukey)
void fft(Complex* x, int N) {
    if (N <= 1) return;
    
    // Divide
    Complex* even = (Complex*)malloc(N/2 * sizeof(Complex));
    Complex* odd = (Complex*)malloc(N/2 * sizeof(Complex));
    
    for (int i = 0; i < N/2; i++) {
        even[i] = x[i*2];
        odd[i] = x[i*2 + 1];
    }
    
    // Conquer
    fft(even, N/2);
    fft(odd, N/2);
    
    // Combine
    for (int k = 0; k < N/2; k++) {
        float angle = -2.0f * M_PI * k / N;
        Complex t;
        t.real = cosf(angle) * odd[k].real - sinf(angle) * odd[k].imag;
        t.imag = cosf(angle) * odd[k].imag + sinf(angle) * odd[k].real;
        
        x[k].real = even[k].real + t.real;
        x[k].imag = even[k].imag + t.imag;
        
        x[k + N/2].real = even[k].real - t.real;
        x[k + N/2].imag = even[k].imag - t.imag;
    }
    
    free(even);
    free(odd);
}

// Inverse FFT
void ifft(Complex* x, int N) {
    // Conjugate
    for (int i = 0; i < N; i++) {
        x[i].imag = -x[i].imag;
    }
    
    // Forward FFT
    fft(x, N);
    
    // Conjugate and scale
    for (int i = 0; i < N; i++) {
        x[i].real /= N;
        x[i].imag = -x[i].imag / N;
    }
}

// Calculate magnitude
static inline float magnitude(Complex c) {
    return sqrtf(c.real * c.real + c.imag * c.imag);
}

// Calculate phase
static inline float phase(Complex c) {
    return atan2f(c.imag, c.real);
}

// Wrap phase to [-pi, pi]
static inline float wrap_phase(float phase) {
    while (phase > M_PI) phase -= 2.0f * M_PI;
    while (phase < -M_PI) phase += 2.0f * M_PI;
    return phase;
}

// Phase vocoder pitch shifting
AudioBuffer* phase_vocoder_pitch_shift(AudioBuffer* input, float pitch_ratio) {
    printf("Starting Phase Vocoder pitch shift with ratio: %.3f\n", pitch_ratio);
    
    // Clamp pitch ratio
    if (pitch_ratio < 0.5f) pitch_ratio = 0.5f;
    if (pitch_ratio > 2.0f) pitch_ratio = 2.0f;
    
    // For pitch shifting: time-stretch by pitch_ratio, then resample by 1/pitch_ratio
    // pitch_ratio > 1 means higher pitch:
    //   - time-stretch by 1.2x (longer, same pitch)
    //   - resample by 0.833x (compress back, raises pitch)
    // Result: same duration, pitch increased by 1.2x
    float time_stretch_ratio = pitch_ratio;
    
    // Create temporary buffer for time-stretched audio
    int stretched_length = (int)(input->length * time_stretch_ratio * 1.2f);
    float* temp_output = (float*)calloc(stretched_length, sizeof(float));
    
    // Allocate working buffers
    float* window = (float*)malloc(FFT_SIZE * sizeof(float));
    Complex* fft_in = (Complex*)malloc(FFT_SIZE * sizeof(Complex));
    Complex* fft_out = (Complex*)malloc(FFT_SIZE * sizeof(Complex));
    float* magnitude_buf = (float*)malloc(FFT_SIZE * sizeof(float));
    float* phase_buf = (float*)malloc(FFT_SIZE * sizeof(float));
    float* last_phase = (float*)calloc(FFT_SIZE, sizeof(float));
    float* sum_phase = (float*)calloc(FFT_SIZE, sizeof(float));
    
    // Generate Hanning window
    for (int i = 0; i < FFT_SIZE; i++) {
        window[i] = hanning(i, FFT_SIZE);
    }
    
    // Calculate analysis and synthesis hop sizes for TIME STRETCHING
    int analysis_hop = HOP_SIZE;
    int synthesis_hop = (int)(HOP_SIZE * time_stretch_ratio);
    if (synthesis_hop < 1) synthesis_hop = 1;
    
    printf("FFT size: %d, Analysis hop: %d, Synthesis hop: %d (time stretch: %.3f)\n", 
           FFT_SIZE, analysis_hop, synthesis_hop, time_stretch_ratio);
    
    int num_frames = (input->length - FFT_SIZE) / analysis_hop;
    int output_pos = 0;
    
    // Process each frame
    for (int frame = 0; frame < num_frames; frame++) {
        int input_pos = frame * analysis_hop;
        
        // Skip if we're too close to the end
        if (input_pos + FFT_SIZE > input->length) break;
        if (output_pos + FFT_SIZE > stretched_length) break;
        
        // 1. Extract and window the frame
        for (int i = 0; i < FFT_SIZE; i++) {
            fft_in[i].real = input->data[input_pos + i] * window[i];
            fft_in[i].imag = 0.0f;
        }
        
        // 2. Forward FFT
        fft(fft_in, FFT_SIZE);
        
        // 3. Extract magnitude and phase
        for (int i = 0; i < FFT_SIZE; i++) {
            magnitude_buf[i] = magnitude(fft_in[i]);
            phase_buf[i] = phase(fft_in[i]);
        }
        
        // 4. Phase vocoder processing
        for (int i = 0; i < FFT_SIZE / 2; i++) {
            // Calculate phase difference
            float phase_diff = phase_buf[i] - last_phase[i];
            last_phase[i] = phase_buf[i];
            
            // Wrap phase difference to [-pi, pi]
            phase_diff = wrap_phase(phase_diff);
            
            // Calculate instantaneous frequency
            float expected_phase_diff = 2.0f * M_PI * i * analysis_hop / FFT_SIZE;
            float freq_deviation = (phase_diff - expected_phase_diff);
            
            // Unwrap frequency deviation
            freq_deviation = wrap_phase(freq_deviation);
            
            // Calculate true frequency
            float true_freq = 2.0f * M_PI * i / FFT_SIZE + freq_deviation / analysis_hop;
            
            // Accumulate phase for synthesis
            sum_phase[i] += true_freq * synthesis_hop;
            
            // Reconstruct complex spectrum with new phase
            fft_out[i].real = magnitude_buf[i] * cosf(sum_phase[i]);
            fft_out[i].imag = magnitude_buf[i] * sinf(sum_phase[i]);
        }
        
        // Mirror for negative frequencies
        for (int i = FFT_SIZE / 2; i < FFT_SIZE; i++) {
            fft_out[i].real = fft_out[FFT_SIZE - i].real;
            fft_out[i].imag = -fft_out[FFT_SIZE - i].imag;
        }
        
        // 5. Inverse FFT
        ifft(fft_out, FFT_SIZE);
        
        // 6. Overlap-add to temp output with window
        for (int i = 0; i < FFT_SIZE; i++) {
            if (output_pos + i < stretched_length) {
                temp_output[output_pos + i] += fft_out[i].real * window[i];
            }
        }
        
        // Advance output position
        output_pos += synthesis_hop;
    }
    
    printf("Processed %d frames, stretched output length: %d samples\n", num_frames, output_pos);
    
    // Normalize time-stretched audio to account for overlap-add
    float overlap_norm = 2.0f / OVERLAP_FACTOR;
    for (int i = 0; i < output_pos && i < stretched_length; i++) {
        temp_output[i] *= overlap_norm;
    }
    
    // Now resample the time-stretched audio back to original length
    // This completes the pitch shift: time stretch * resample = pitch change with same duration
    AudioBuffer* output = (AudioBuffer*)malloc(sizeof(AudioBuffer));
    output->length = input->length;
    output->sample_rate = input->sample_rate;
    output->data = (float*)malloc(output->length * sizeof(float));
    
    // Simple linear interpolation resampling
    float ratio = (float)output_pos / output->length;
    for (int i = 0; i < output->length; i++) {
        float pos = i * ratio;
        int idx = (int)pos;
        float frac = pos - idx;
        
        if (idx + 1 < output_pos) {
            output->data[i] = temp_output[idx] * (1.0f - frac) + temp_output[idx + 1] * frac;
        } else if (idx < output_pos) {
            output->data[i] = temp_output[idx];
        } else {
            output->data[i] = 0.0f;
        }
    }
    
    // Final normalization
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
    free(temp_output);
    free(window);
    free(fft_in);
    free(fft_out);
    free(magnitude_buf);
    free(phase_buf);
    free(last_phase);
    free(sum_phase);
    
    printf("Phase vocoder pitch shift complete\n");
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
    AudioBuffer* output = phase_vocoder_pitch_shift(input, pitch_ratio);
    
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