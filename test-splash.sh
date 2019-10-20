#!/bin/bash

# Start the plymouthd, show the splash, then stop it again after
# a short period (can be passed as the first arg)

(
    killall -TERM plymouthd

    sleep 1

    killall -KILL plymouthd

    sleep 2

    plymouthd --debug < /dev/null  2>&1 &

    sleep 2

    plymouth show-splash &

    sleep 2

    chvt 1 &

    sleep "${1:-10}"

    chvt 5 &

    plymouth hide-splash &

    sleep 2;

    plymouth quit &

    sleep 2

    killall -TERM plymouthd

    sleep 2

    killall -KILL plymouthd

    sleep 2

    chvt 5 &

) &

