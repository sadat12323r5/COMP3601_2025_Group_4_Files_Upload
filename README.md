## Real-Time Audio Retuning System with KV260

A COMP3601 embedded systems project implementing a hardware–software audio processing pipeline on the AMD/Xilinx Kria KV260 platform.

### Overview

This project captures live audio from a MEMS I²S microphone, detects pitch in software, retunes the recording to match a reference WAV file, saves the processed result to an SD card, and plays the retuned audio through a speaker via an I²S amplifier.

### Key Capabilities

- Real-time audio capture from an I²S MEMS microphone (SPH0645 family)
- AXI DMA streaming between PL and PS for low-latency transfer
- WAV file creation and SD card storage (FatFs)
- Pitch detection (YIN / autocorrelation / FFT-based options)
- Pitch shifting via time-stretching + resampling / phase vocoder
- Real-time and saved playback through a MAX98357A Class-D I²S amplifier

### Demo Flow (high level)

1. Place a reference file named `e.wav` on the SD card — this is the target pitch reference.
2. System records ~7 seconds from the microphone via the PL I²S receiver and S2MM DMA.
3. PS computes the fundamental frequency (F₀) of the recorded audio and of `e.wav`.
4. PS computes the pitch ratio and applies pitch shifting to the recording.
5. Outputs:
	 - `shifted.wav` — processed WAV file written to the SD card
	 - Real-time playback — processed stream returned to PL via MM2S DMA and played through the speaker

### System Architecture (summary)

- **PL (Programmable Logic):**
	- I²S Receiver: captures microphone PCM and pushes samples into a FIFO
	- Mic FIFO & AXI DMA (S2MM): buffers and streams samples into PS DDR
	- AXI DMA (MM2S), Speaker FIFO, I²S Transmitter: moves processed frames back to PL for playback
	- Amplifier pipeline (gain/clipping) before the MAX98357A

- **PS (Processing System, Bare-metal C):**
	- Reads DMA buffers, converts 24-bit mic PCM to 16-bit WAV PCM
	- Performs pitch detection on reference and recorded audio
	- Executes pitch shifting and produces an output buffer
	- Writes `shifted.wav` (FatFs) and streams processed buffers back to PL for playback

### Software Pipeline Details

- Pitch detection: options implemented include the YIN algorithm, autocorrelation, and FFT-based methods. These compute the fundamental frequency F₀.
- Pitch shifting: compute pitch ratio = F₀(reference) / F₀(input). Use time-stretching + resampling or a phase vocoder to produce a pitch-corrected PCM buffer while preserving duration and quality as much as possible.

### Files of interest

- `Hardware/` — Vivado project, PL sources, and implementation outputs
- `Software/` — PS projects and source code for capture, analysis, shifting, and file I/O
- `DSP Hardware/` — VHDL for DSP building blocks (filters, envelope follower, etc.)
- `Testing/` — test programs and tools used during development

### Build / Run (quick notes)

- Open `Hardware/Lab3.xpr` in Vivado (or the KV260 flow) to review the PL design and regenerate bitstream if needed.
- Build or flash the PS software from `Software/` using the board's SDK or standalone toolchain used in the course.
- Ensure an SD card with `e.wav` is inserted and the board has power and the microphone/speaker connected.

### Known hardware used

- MEMS I²S microphone: SPH0645 (Adafruit breakout)
- I²S amplifier: MAX98357A
- Target board: AMD/Xilinx Kria KV260 Vision AI

### Features

- Real-time capture and playback
- Full PL↔PS round-trip audio pipeline using AXI DMA
- WAV recording with correct headers
- Modular VHDL components for FIFO, I²S RX/TX, and amplifier logic
- SD card file handling using FatFs

### Contributors

- Sadat Kabir — SD file system & WAV handling, I²S transmitter for speaker
- Ben Huntsman — Output cleanup, SD file handling improvements, integration
- Dylan Loh — Testing and QA, I²S transmitter assistance
- Bryan Bong — Pitch detection and pitch shifting algorithms

### License

Educational use only — COMP3601 coursework.

### Contact / Next steps

For development details, tests, or to reproduce the demo, open the `Hardware/` and `Software/` folders. If you want, I can also:

- add a short `CONTRIBUTING.md` or `BUILD.md` with step-by-step build/flash instructions
- extract exact build commands from `Software/` and add them to this README

flowchart TD

    subgraph SD[SD Card (SD1)]
        E[e.wav (reference)]
        S[shifted.wav (output)]
    end

    subgraph PS[Processing System (ARM Cortex-A53)]
        A1[DMA S2MM Handler]
        A2[WAV Writer (FatFs)]
        A3[Pitch Detection]
        A4[Pitch Shifting Engine]
        A5[DMA MM2S Streamer]
    end

    subgraph PL[Programmable Logic (PL)]
        subgraph INPUT[Microphone Path]
            RX[I2S Receiver\n(SPH0645)]
            FIFO_IN[Input FIFO]
            DMA_S2MM[AXI DMA S2MM]
        end

        subgraph OUTPUT[Speaker Path]
            DMA_MM2S[AXI DMA MM2S]
            FIFO_OUT[Output FIFO]
            TX[I2S Transmitter]
            AMP[MAX98357A I2S Amplifier]
        end
    end

    Mic[(I2S MEMS Microphone)]
    Speaker[(Speaker Output)]

    Mic -->|I2S: DOUT, BCLK, LRCLK| RX --> FIFO_IN --> DMA_S2MM --> PS

    PS -->|Processed PCM| DMA_MM2S --> FIFO_OUT --> TX --> AMP --> Speaker

    E --> A3
    A4 --> S
    A4 --> A5
