#!/bin/bash

set -eux

JULIA=julia-0.5.0
MACHINEFILE_MAX=../workspace/machine-files/max-processes-each.machinefile

cd `dirname $0`/../..
cd pipeline
$JULIA --machinefile $MACHINEFILE_MAX -e \
    "reload(\"Pipeline\"); @time Pipeline.peel($1, \"$2\")"

