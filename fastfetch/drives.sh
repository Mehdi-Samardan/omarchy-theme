#!/bin/bash
# NVMe drives: short model, size (reads sysfs only, so it's instant)
shopt -s nullglob
out=()
for n in /sys/class/nvme/nvme*; do
  model=$(sed 's/ *$//' "$n/model"); model=${model%% SSD*}
  sectors=$(cat "/sys/block/$(basename "$n")n1/size" 2>/dev/null)
  [[ -n $sectors ]] || continue
  out+=("$model $(( sectors * 512 / 1000000000 ))G")
done
(IFS=,; echo "${out[*]}" | sed 's/,/ · /g')
