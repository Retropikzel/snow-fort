#!/bin/sh

snow-chibi --host=https://retropikzel.neocities.org --use-curl=t update
chibi-scheme update.scm s/repo.scm ${HOME}/.snow/repo/*.scm
