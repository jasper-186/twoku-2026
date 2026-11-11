#!/bin/sh
#
# Container entrypoint.
#
# Applies migrations against the configured database and then hands over to
# gunicorn. Migrations run here rather than at build time because the
# database may live on a mounted volume that does not exist in the image.

set -e

echo "Applying database migrations..."
python manage.py migrate --noinput

echo "Starting gunicorn..."
exec gunicorn --bind 0.0.0.0:8080 --workers 4 twitchauth.wsgi:application
