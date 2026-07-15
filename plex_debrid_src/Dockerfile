FROM python:3.12-slim

WORKDIR /app

# Install dependencies first to leverage Docker layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application source
COPY . .

ENV TERM=xterm
ENV PYTHONUNBUFFERED=1

# Config is mounted at /config by docker-compose
CMD ["python", "./main.py", "--config-dir", "/config"]
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TERM=xterm

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . ./

CMD ["python", "./main.py", "--config-dir", "/config", "-e", "TERM=xterm"]
