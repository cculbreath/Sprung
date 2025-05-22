#!/bin/bash
# LLM Compatibility Test Runner
# This script runs the LLM compatibility tests with API keys from environment variables

# Set color codes for output formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===== PhysCloudResume LLM Compatibility Test Runner =====${NC}"
echo -e "${BLUE}Testing RecommendJobButton functionality across different LLM providers${NC}"
echo ""

# Check for required API keys in environment
echo -e "${YELLOW}Checking for required API keys in environment...${NC}"

# Initialize status variables
OPENAI_KEY_PRESENT=false
ANTHROPIC_KEY_PRESENT=false
GROK_KEY_PRESENT=false
GEMINI_KEY_PRESENT=false

# Check each API key
if [ -n "$OPENAI_API_KEY" ]; then
  echo -e "✅ ${GREEN}OpenAI API key found${NC}"
  OPENAI_KEY_PRESENT=true
else
  echo -e "⚠️ ${YELLOW}OpenAI API key not found, OpenAI models will be skipped${NC}"
fi

if [ -n "$ANTHROPIC_API_KEY" ]; then
  echo -e "✅ ${GREEN}Anthropic API key found${NC}"
  ANTHROPIC_KEY_PRESENT=true
else
  echo -e "⚠️ ${YELLOW}Anthropic API key not found, Claude models will be skipped${NC}"
fi

if [ -n "$GROK_API_KEY" ]; then
  echo -e "✅ ${GREEN}Grok API key found${NC}"
  GROK_KEY_PRESENT=true
else
  echo -e "⚠️ ${YELLOW}Grok API key not found, Grok models will be skipped${NC}"
fi

if [ -n "$GEMINI_API_KEY" ]; then
  echo -e "✅ ${GREEN}Gemini API key found${NC}"
  GEMINI_KEY_PRESENT=true
else
  echo -e "⚠️ ${YELLOW}Gemini API key not found, Gemini models will be skipped${NC}"
fi

# Confirm test run
echo ""
echo -e "${YELLOW}This test will make real API calls to LLM providers, which may incur charges.${NC}"
read -p "Do you want to continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${RED}Test cancelled.${NC}"
  exit 0
fi

# Define models to test based on available API keys
echo -e "${BLUE}Configuring tests based on available API keys...${NC}"
MODELS_TO_TEST=()

if [ "$OPENAI_KEY_PRESENT" = true ]; then
  MODELS_TO_TEST+=("gpt-4.1")
  MODELS_TO_TEST+=("o3")
  MODELS_TO_TEST+=("o4-mini")
  echo -e "✅ ${GREEN}Will test OpenAI models: gpt-4.1, o3, o4-mini${NC}"
fi

if [ "$ANTHROPIC_KEY_PRESENT" = true ]; then
  MODELS_TO_TEST+=("claude-3-5-haiku-20241022")
  echo -e "✅ ${GREEN}Will test Anthropic models: claude-3-5-haiku-20241022${NC}"
fi

if [ "$GROK_KEY_PRESENT" = true ]; then
  MODELS_TO_TEST+=("grok-3-mini-fast")
  echo -e "✅ ${GREEN}Will test Grok models: grok-3-mini-fast${NC}"
fi

if [ "$GEMINI_KEY_PRESENT" = true ]; then
  MODELS_TO_TEST+=("gemini-2.0-flash")
  echo -e "✅ ${GREEN}Will test Gemini models: gemini-2.0-flash${NC}"
fi

# If no API keys are available, exit
if [ ${#MODELS_TO_TEST[@]} -eq 0 ]; then
  echo -e "${RED}No API keys available for testing. Exiting.${NC}"
  exit 1
fi

# Run the tests
echo ""
echo -e "${BLUE}Running LLM compatibility tests...${NC}"
echo -e "${YELLOW}This may take several minutes depending on model response times.${NC}"

export XCT_MODELS_TO_TEST=$(IFS=,; echo "${MODELS_TO_TEST[*]}")
# Use xcodebuild instead of swift test
xcodebuild test -project ../PhysCloudResume.xcodeproj -scheme PhysCloudResume -testPlan LLMCompatibilityTests

# Check the test result
TEST_RESULT=$?

if [ $TEST_RESULT -eq 0 ]; then
  echo -e "${GREEN}All LLM compatibility tests passed!${NC}"
else
  echo -e "${RED}Some LLM compatibility tests failed. Check the test output for details.${NC}"
fi

# Create a report summary
echo ""
echo -e "${BLUE}Test Summary:${NC}"
echo "Date: $(date)"
echo "Models Tested: ${MODELS_TO_TEST[@]}"
echo "Test Result: $([ $TEST_RESULT -eq 0 ] && echo 'PASS' || echo 'FAIL')"

exit $TEST_RESULT
