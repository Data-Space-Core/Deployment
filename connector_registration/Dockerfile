# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory in the container
WORKDIR /app

# Copy the current directory contents into the container
COPY . /app

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt \
    && adduser --disabled-password --gecos "" appuser \
    && chown -R appuser:appuser /app

# Expose the port the app runs on
EXPOSE 5001

# Define environment variable
ENV PYTHONUNBUFFERED=1

# Run the application
USER appuser
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "app:app"]
