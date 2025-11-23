FROM ruby:3.2.9

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    postgresql-client \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install Ruby dependencies
RUN bundle install

# Copy app code
COPY . .

# Expose port 5000
EXPOSE 5000

# Default command
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:5000", "config.ru"]
