FROM python:3.14-trixie

WORKDIR /app

RUN mkdir -p /app/static

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Upgrade pip first
RUN pip install --no-cache-dir --upgrade pip

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy project files
COPY . .

# Collect static files
RUN python manage.py collectstatic --noinput || true

# Defaults for a self-hosted deployment. Override them with `docker run -e`
# or the environment section of a compose file. Nothing secret is set here -
# the Twitch client secret and the Django secret key must be supplied.
ENV DJANGO_DEBUG=false \
    DJANGO_BASE_URL=https://twoku-web.clstr.dev

# Expose port
EXPOSE 8080

# Migrations run at startup, not at build time, because the database may
# live on a volume that is not part of the image.
RUN chmod +x docker-entrypoint.sh
CMD ["./docker-entrypoint.sh"]
