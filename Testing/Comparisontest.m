[orig, fs1] = audioread("REC_001.WAV");
[shift, fs2] = audioread("OUT_001.WAV");

fprintf("fs original = %d Hz, fs shifted = %d Hz\n", fs1, fs2);

% Make sure sample rates match
if fs1 ~= fs2
    warning("Sample rates differ! Results may be off.");
end
fs = fs1;

% Use mono (first channel) if stereo
if size(orig,2) > 1, orig = orig(:,1); end
if size(shift,2) > 1, shift = shift(:,1); end

%% 2. Pick a clean 1-second segment from the middle of each (for SNR/THD)

N = fs;  % 1 second

% Original
if length(orig) > N
    start1   = floor((length(orig) - N)/2) + 1;
    seg_orig = orig(start1:start1+N-1);
else
    seg_orig = orig;
end

% Shifted
if length(shift) > N
    start2    = floor((length(shift) - N)/2) + 1;
    seg_shift = shift(start2:start2+N-1);
else
    seg_shift = shift;
end

%% 3. SNR and THD for original and shifted

snr_orig  = snr(seg_orig);
snr_shift = snr(seg_shift);

[thd_orig_db, ~, ~]  = thd(seg_orig,  fs);
[thd_shift_db, ~, ~] = thd(seg_shift, fs);

fprintf("\n=== SNR / THD RESULTS ===\n");
fprintf("Original:    SNR = %.2f dB, THD = %.2f dB\n", snr_orig,  thd_orig_db);
fprintf("Pitch-shift: SNR = %.2f dB, THD = %.2f dB\n", snr_shift, thd_shift_db);

%% 4. Spectrograms before and after pitch shift

figure;

subplot(2,2,1);
t_orig = (0:length(orig)-1)/fs;
plot(t_orig, orig);
title("Original audio - waveform");
xlabel("Time (s)");
ylabel("Amplitude");

subplot(2,2,3);
spectrogram(orig, 1024, 768, 1024, fs, 'yaxis');
title("Original audio - spectrogram");
ylabel("Frequency (Hz)");
xlabel("Time (s)");
colorbar;

subplot(2,2,2);
t_shift = (0:length(shift)-1)/fs;
plot(t_shift, shift);
title("Pitch-shifted audio - waveform");
xlabel("Time (s)");
ylabel("Amplitude");

subplot(2,2,4);
spectrogram(shift, 1024, 768, 1024, fs, 'yaxis');
title("Pitch-shifted audio - spectrogram");
ylabel("Frequency (Hz)");
xlabel("Time (s)");
colorbar;

sgtitle("Original vs Pitch-shifted Audio (Waveform + Spectrogram)");

%% 5. FFT-based pitch ratio check (dominant frequency, ignoring DC)

Nfft = 4096;    % FFT size (power of 2, decent resolution)

% High-pass: remove DC offset
seg_orig_hp  = seg_orig  - mean(seg_orig);
seg_shift_hp = seg_shift - mean(seg_shift);

% Window the one second segments to reduce spectral leakage
w = hann(length(seg_orig_hp));

% Original
Xo     = fft(seg_orig_hp .* w, Nfft);
Xo_mag = abs(Xo(1:Nfft/2));               % positive freqs only
freqs  = (0:Nfft/2-1)*(fs/Nfft);

% Only search for peaks in a sensible audio range, e.g. 50–4000 Hz
fmin = 50;
fmax = 4000;
search_idx = freqs >= fmin & freqs <= fmax;

[~, rel_k0] = max(Xo_mag(search_idx));
valid_freqs = freqs(search_idx);
f_orig = valid_freqs(rel_k0);

% Shifted
Xs     = fft(seg_shift_hp .* w, Nfft);
Xs_mag = abs(Xs(1:Nfft/2));

[~, rel_k1] = max(Xs_mag(search_idx));
f_shift = valid_freqs(rel_k1);

ratio      = f_shift / f_orig;
semitones  = 12*log2(ratio);

fprintf("\n=== FFT PEAK / PITCH RATIO CHECK  ===\n");
fprintf("Dominant freq (original)  ≈ %.2f Hz\n", f_orig);
fprintf("Dominant freq (shifted)   ≈ %.2f Hz\n", f_shift);
fprintf("Frequency ratio           ≈ %.3f\n", ratio);
fprintf("Estimated semitone shift  ≈ %.2f semitones\n", semitones);

%waveform testing
figure;
plot(seg_orig(1:2000)); hold on;
plot(seg_shift(1:2000));
legend('Original','Shifted');
title('Waveform Comparison (Zoomed)');
xlabel('Samples');
ylabel('Amplitude');
