#!/bin/bash

# Simple test script for vLLM server
# Usage: 
#   ./request.sh list [PORT]                    - List available models
#   ./request.sh <MODEL_NAME> [PORT]            - Send chat request
# 
# Example: 
#   ./request.sh list
#   ./request.sh "Qwen/Qwen2.5-0.5B-Instruct" 8000

# Parse arguments
if [ $# -eq 0 ]; then
    echo "Usage:"
    echo "  $0 list [PORT]                    - List available models"
    echo "  $0 <MODEL_NAME> [PORT]            - Send chat request"
    echo ""
    echo "Examples:"
    echo "  $0 list                           - List models on port 8000"
    echo "  $0 list 8001                      - List models on port 8001"
    echo "  $0 \"Qwen/Qwen2.5-0.5B-Instruct\" 8000 - Chat with model"
    exit 1
fi

# Check if first argument is "list"
if [ "$1" = "list" ]; then
    PORT=${2:-8000}
    BASE_URL="http://localhost:${PORT}"
    
    echo "=== Available Models at ${BASE_URL} ==="
    echo ""
    
    curl -s "${BASE_URL}/v1/models" | jq '.' || curl -s "${BASE_URL}/v1/models"
    echo ""
    exit 0
fi

MODEL="$1"
PORT=${2:-8000}
BASE_URL="http://localhost:${PORT}"

echo "=== Testing vLLM Chat at ${BASE_URL} ==="
echo "Model: ${MODEL}"
echo ""

curl -s "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL}\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"Say hello in one sentence\"}
    ],
    \"max_tokens\": 50,
    \"temperature\": 0.7
  }"
echo ""

