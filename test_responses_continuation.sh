#\!/bin/bash

# This script tests the OpenAI Responses API with conversation continuation
# Usage: ./test_responses_continuation.sh "Your message here" "previous_response_id"

# Check if the API key is set
if [ -z "$OPENAI_API_KEY" ]; then
  echo "Error: OPENAI_API_KEY environment variable is not set."
  echo "Please set it with: export OPENAI_API_KEY=your_api_key_here"
  exit 1
fi

# Get the message from command line arguments or use a default
MESSAGE="${1:-Hello again, can you tell me more?}"
PREVIOUS_RESPONSE_ID="$2"

# Check if previous_response_id was provided
if [ -z "$PREVIOUS_RESPONSE_ID" ]; then
  echo "Error: previous_response_id is required."
  echo "Usage: ./test_responses_continuation.sh \"Your message\" \"previous_response_id\""
  exit 1
fi

# Create a JSON payload
JSON_PAYLOAD=$(cat <<EOF_JSON
{
  "model": "gpt-4o",
  "input": "$MESSAGE",
  "temperature": 0.7,
  "previous_response_id": "$PREVIOUS_RESPONSE_ID"
}
EOF_JSON
)

# Make the API request
echo "Sending continuation request to OpenAI Responses API..."
curl -s -X POST https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "$JSON_PAYLOAD" | jq .
