#!/bin/bash

# Setup core dump pattern and limits
echo "/opt/%e.%s.core" > /proc/sys/kernel/core_pattern
ulimit -c unlimited
echo "Core dump pattern set to /opt/%e.%s.core."

exit 0
