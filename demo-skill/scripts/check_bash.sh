#!/usr/bin/env bash

echo "bash $BASH_VERSION"
echo "arg_count=$#"
printf 'arg1=%s\n' "${1-}"
printf 'arg2=%s\n' "${2-}"
