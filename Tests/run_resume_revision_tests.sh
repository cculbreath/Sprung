#!/bin/bash

# Run LLM Tests for Resume Revision Workflow
# This script runs the tests for the Resume Revision Workflow

# Set up colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Resume Revision Workflow Test Runner${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Check for API keys in environment variables
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${YELLOW}WARNING: OPENAI_API_KEY not set in environment. OpenAI models will be skipped.${NC}"
    echo -e "${YELLOW}Set with: export OPENAI_API_KEY=\"your_key_here\"${NC}"
else
    echo -e "${GREEN}✓ OPENAI_API_KEY found${NC}"
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo -e "${YELLOW}WARNING: ANTHROPIC_API_KEY not set in environment. Claude models will be skipped.${NC}"
    echo -e "${YELLOW}Set with: export ANTHROPIC_API_KEY=\"your_key_here\"${NC}"
else
    echo -e "${GREEN}✓ ANTHROPIC_API_KEY found${NC}"
fi

if [ -z "$GROK_API_KEY" ]; then
    echo -e "${YELLOW}WARNING: GROK_API_KEY not set in environment. Grok models will be skipped.${NC}"
    echo -e "${YELLOW}Set with: export GROK_API_KEY=\"your_key_here\"${NC}"
else
    echo -e "${GREEN}✓ GROK_API_KEY found${NC}"
fi

if [ -z "$GEMINI_API_KEY" ]; then
    echo -e "${YELLOW}WARNING: GEMINI_API_KEY not set in environment. Gemini models will be skipped.${NC}"
    echo -e "${YELLOW}Set with: export GEMINI_API_KEY=\"your_key_here\"${NC}"
else
    echo -e "${GREEN}✓ GEMINI_API_KEY found${NC}"
fi

echo ""
echo -e "${BLUE}Starting tests...${NC}"
echo ""

# Function to run a specific test
run_test() {
    TEST_NAME=$1
    echo -e "${BLUE}Running $TEST_NAME...${NC}"
    
    # Run the test
    xcrun xctest -XCTest $TEST_NAME PhysCloudResumeTests.xctest
    
    # Check result
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $TEST_NAME passed${NC}"
        return 0
    else
        echo -e "${RED}✗ $TEST_NAME failed${NC}"
        return 1
    fi
}

# Run the tests in sequence
echo -e "${BLUE}Step 1: Testing PDF Rendering${NC}"
run_test "PhysCloudResumeTests.ResumePDFRendererTests"
PDF_RESULT=$?

echo -e "${BLUE}Step 2: Testing AI Communicator${NC}"
run_test "PhysCloudResumeTests.AiCommunicatorTests"
AI_RESULT=$?

echo -e "${BLUE}Step 3: Testing Full Resume Revision Workflow${NC}"
run_test "PhysCloudResumeTests.ResumeRevisionWorkflowTests"
WORKFLOW_RESULT=$?

# Print summary
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}              SUMMARY               ${NC}"
echo -e "${BLUE}======================================${NC}"

if [ $PDF_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ PDF Rendering Tests: PASSED${NC}"
else
    echo -e "${RED}✗ PDF Rendering Tests: FAILED${NC}"
fi

if [ $AI_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ AI Communicator Tests: PASSED${NC}"
else
    echo -e "${RED}✗ AI Communicator Tests: FAILED${NC}"
fi

if [ $WORKFLOW_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Resume Revision Workflow Tests: PASSED${NC}"
else
    echo -e "${RED}✗ Resume Revision Workflow Tests: FAILED${NC}"
fi

# Overall result
if [ $PDF_RESULT -eq 0 ] && [ $AI_RESULT -eq 0 ] && [ $WORKFLOW_RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}Some tests failed. Please check the output above for details.${NC}"
    exit 1
fi
