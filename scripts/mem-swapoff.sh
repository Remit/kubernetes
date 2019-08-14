#!/bin/sh

if [ $(wc -l < /proc/swaps) -gt 1 ]; then
  echo "Swap is on, trying to turn it off and reboot..."
  sudo swapoff -a
  sudo sed -i '/ swap / s/^/#/' /etc/fstab
  sudo reboot
else
  echo "Swap is already set to off"
fi
