#\!/bin/bash

# This script tests the OpenAI Responses API using your OpenAI API key
# Usage: ./test_responses_api.sh "Your message here"

# Check if the API key is set
if [ -z "$OPENAI_API_KEY" ]; then
  echo "Error: OPENAI_API_KEY environment variable is not set."
  echo "Please set it with: export OPENAI_API_KEY=your_api_key_here"
  exit 1
fi

# Get the message from command line arguments or use a default
MESSAGE="${1:-Hello, how are you today?}"

# Create a JSON payload
JSON_PAYLOAD=$(cat <<EOF_JSON
{
  "model": "gpt-4o",
  "input": "$MESSAGE",
  "temperature": 0.7
}
EOF_JSON
)

# Make the API request
echo "Sending request to OpenAI Responses API..."
curl -s -X POST https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "$JSON_PAYLOAD" | jq .

echo ""
echo "If you want to test with a previous_response_id, use the id from the response above."
