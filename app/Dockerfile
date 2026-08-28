# syntax=docker/dockerfile:1.7
#
# PYTHON_VERSION is intentionally NOT hardcoded here beyond a fallback default.
# The Jenkinsfile reads app/base-image.env and passes it as --build-arg, so
# toggling that file (via scripts/break-the-build.sh) changes what gets built
# without editing this file. The default below matches the vulnerable demo
# starting state for plain `docker build .` runs outside Jenkins.
ARG PYTHON_VERSION=3.9-slim-buster

FROM python:${PYTHON_VERSION} AS builder
WORKDIR /build
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --prefix=/install -r requirements.txt

FROM python:${PYTHON_VERSION}
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .

ARG GIT_COMMIT=unknown
ARG BUILD_NUMBER=local
ARG IMAGE_TAG=dev
ENV GIT_COMMIT=${GIT_COMMIT} \
    BUILD_NUMBER=${BUILD_NUMBER} \
    IMAGE_TAG=${IMAGE_TAG}

EXPOSE 8000
USER 1000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
