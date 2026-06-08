FROM ruby:3.2.2-slim

# Install system dependencies
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    postgresql-client \
    python3 \
    python3-pip \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install Ruby dependencies
RUN bundle install

# Copy the rest of the application
COPY . .

# Install Python image-processing dependencies for the DTF halftone tool
RUN pip3 install --no-cache-dir --break-system-packages -r requirements-python.txt

# Expose port 5000
EXPOSE 5000

# Default command
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
