#!/bin/bash

# MAKE SURE TO RUN MAKE IN PARENT DIRECTORY BEFORE USING
../c2ll < $1 > testing.ll
llc --relocation-model=pic testing.ll -o testing.s
gcc testing.s -o testing
