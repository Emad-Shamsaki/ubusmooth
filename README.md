# UbuSmooth — Make Ubuntu Run Smoother

**UbuSmooth** is a small, safe, and reversible set of system tweaks for Ubuntu designed to reduce memory/disk overhead, improve responsiveness, and let you measure the difference with clear before/after benchmarks.

---

## How It Works

1. **Measure performance first** with simple, repeatable tests.
2. **Apply safe optimizations**:
   - Enable compressed swap in RAM (**zram**)
   - Tune kernel memory settings (low swappiness, lower cache pressure)
   - Install and enable **TLP** for better power/performance balance
   - Enable weekly **SSD TRIM** for sustained disk speed
   - Clean unused packages and cache
   - (Optional) Disable XFCE compositing for older GPUs
3. **Reboot** to ensure all tweaks are active.
4. **Measure performance again** using the same tests.
5. **Compare results** to see actual changes.
6. **Revert anytime** with one command.

---

## Quick Start

```bash
# Clone your copy
git clone https://github.com/<you>/ubusmooth.git
cd ubusmooth

# Measure baseline performance (no tweaks yet)
./bench.sh baseline

# Apply tweaks
sudo bash ubusmooth.sh --all

# Reboot to activate everything
sudo reboot

# After reboot, run benchmarks again
./bench.sh ubusmooth

# View results in bench/results.csv
cat bench/results.csv


# Revert Changes
sudo bash ubusmooth.sh --revert

