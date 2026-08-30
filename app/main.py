import os
from datetime import datetime, timezone

from fastapi import FastAPI

app = FastAPI(title="shipit")

BUILD_INFO = {
    "app": "shipit",
    "git_commit": os.getenv("GIT_COMMIT", "unknown"),
    "build_number": os.getenv("BUILD_NUMBER", "local"),
    "image_tag": os.getenv("IMAGE_TAG", "dev"),
}


@app.get("/")
def root():
    return {"message": "shipit is running", **BUILD_INFO}


@app.get("/health")
def health():
    return {"status": "ok", "time": datetime.now(timezone.utc).isoformat()}


@app.get("/version")
def version():
    return BUILD_INFO


@app.get("/ping")
def ping():
    return {"pong": True}
