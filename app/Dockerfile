# Use a lightweight Debian-based Python image. 
# FinOps/Stability: 'slim' avoids the C-binding compilation errors common in 'alpine', keeping builds fast and stable.
FROM python:3.11-slim

# Prevent Python from writing .pyc files (saves disk space)
ENV PYTHONDONTWRITEBYTECODE=1
# Force Python stdout/stderr to be unbuffered so logs stream instantly to external tools
ENV PYTHONUNBUFFERED=1

# Create a non-root user and group.
# SecOps: Traps potential attackers as a low-privilege user, preventing host-node breakouts.
RUN addgroup --system appgroup && adduser --system --group appuser

# Set the working directory inside the container
WORKDIR /app

# Copy ONLY the requirements file first, assigning ownership immediately to save layers.
# FinOps/Speed: Leverages Docker layer caching. Unchanged requirements skip the pip install step on rebuilds.
COPY --chown=appuser:appgroup requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code, assigning ownership immediately.
COPY --chown=appuser:appgroup app.py .

# Switch Docker to execute subsequent commands as the non-root user
USER appuser

# Document the port the application will listen on
EXPOSE 5000

# Tell Docker how to test if the container is healthy using native Python.
# Reliability: Triggers automatic pod restarts in Kubernetes if the application deadlocks.
HEALTHCHECK --interval=30s --timeout=3s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# Start the application using Gunicorn.
# Production Standard: A WSGI server designed to handle concurrent user traffic securely.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]