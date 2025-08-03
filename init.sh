#!/bin/bash

mix archive.install hex igniter_new --force
mix archive.install hex phx_new 1.8.0-rc.4 --force

mix igniter.new live_ai_chat --with phx.new --with-args "--no-ecto" \
  --install ash,ash_phoenix --install ash_csv \
  --install live_debugger,mishka_chelekom --install ash_ai --yes

cd live_ai_chat && mix ash.setup