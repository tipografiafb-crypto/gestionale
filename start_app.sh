#!/bin/bash

# Load environment variables
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

# Start Puma
exec bundle exec puma -b tcp://0.0.0.0:5000 config.ru
