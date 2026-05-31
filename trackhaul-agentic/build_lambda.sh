#!/bin/bash
# build_lambda.sh
# Builds the Lambda deployment package for the agent handler.
# Installs Linux-compatible dependencies, copies source code, and zips.
# Must be run from the trackhaul-agentic root directory.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/lambda_build"
ZIP_PATH="$SCRIPT_DIR/lambda_src/agent_handler.zip"

echo "Cleaning previous build..."
rm -rf "$BUILD_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$BUILD_DIR"

echo "Installing Linux-compatible dependencies..."
pip install \
  --target "$BUILD_DIR" \
  --platform manylinux2014_x86_64 \
  --python-version 3.12 \
  --only-binary=:all: \
  --upgrade \
  langgraph==1.2.2 \
  langchain-core==1.4.0 \
  pydantic==2.13.4 \
  pydantic-core==2.46.4

echo "Copying Lambda handler..."
cp "$SCRIPT_DIR/lambda_src/agent_handler.py" "$BUILD_DIR/agent_handler.py"

echo "Copying agent code..."
cp -r "$SCRIPT_DIR/agents" "$BUILD_DIR/agents"
cp -r "$SCRIPT_DIR/state" "$BUILD_DIR/state"

echo "Removing __pycache__..."
find "$BUILD_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$BUILD_DIR" -name "*.pyc" -delete 2>/dev/null || true

echo "Creating zip..."
cd "$BUILD_DIR"
zip -r "$ZIP_PATH" . -x "*.pyc" -x "*/__pycache__/*"

echo "Done. Package: $ZIP_PATH"
ls -lh "$ZIP_PATH"