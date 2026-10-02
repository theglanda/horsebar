"""Prototype: slap your MacBook and it plays a sound.

Run:  sudo .venv/bin/python prototype/slap.py [--threshold 0.25] [--cooldown 0.4]
Just print slap strengths, no sound:  ... --dry
"""

import argparse
import glob
import os
import random
import subprocess
import sys
import time

from macimu import IMU

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUND_EXT = ('.wav', '.mp3', '.m4a', '.aiff', '.aif', '.caf')


def sound_files():
    files = [f for f in glob.glob(os.path.join(ROOT, 'sounds', '*'))
             if f.lower().endswith(SOUND_EXT)]
    return files or glob.glob('/System/Library/Sounds/*.aiff')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--threshold', type=float, default=0.25, help='slap threshold, g')
    p.add_argument('--cooldown', type=float, default=0.4, help='minimum pause between sounds, s')
    p.add_argument('--floor', type=float, default=0.03, help='ignore anything quieter, g')
    p.add_argument('--dry', action='store_true', help='do not play sounds')
    args = p.parse_args()

    if os.geteuid() != 0:
        sys.exit('must run as root: sudo .venv/bin/python prototype/slap.py')
    if not IMU.available():
        sys.exit('no SPU accelerometer on this Mac (needs M1 Pro / M2 or newer)')

    baseline = None          # slow average = gravity
    alpha = 0.02             # how fast the baseline follows the signal
    last_play = 0.0
    peak, peak_until = 0.0, 0.0

    print(f'listening… threshold {args.threshold} g, cooldown {args.cooldown} s. Ctrl+C to quit')
    with IMU(gyro=False, sample_rate=400) as imu:
        while True:
            for x, y, z in imu.read_accel():
                if baseline is None:
                    baseline = [x, y, z]
                    continue
                dx, dy, dz = x - baseline[0], y - baseline[1], z - baseline[2]
                baseline = [b + alpha * (v - b) for b, v in zip(baseline, (x, y, z))]
                mag = (dx * dx + dy * dy + dz * dz) ** 0.5

                now = time.monotonic()
                # collect the peak of one slap within a 30 ms window
                if mag > args.floor:
                    if now > peak_until:
                        peak = 0.0
                    peak = max(peak, mag)
                    peak_until = now + 0.03
                    continue
                if peak and now > peak_until:
                    hit = peak >= args.threshold
                    ready = now - last_play >= args.cooldown
                    mark = '💥 SOUND' if hit and ready else ('(cooldown)' if hit else '')
                    print(f'slap {peak:.3f} g {mark}')
                    if hit and ready and not args.dry:
                        vol = min(1.0, 0.3 + peak)
                        subprocess.Popen(['afplay', '-v', f'{vol:.2f}', random.choice(sound_files())])
                        last_play = now
                    peak = 0.0
            time.sleep(0.005)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
