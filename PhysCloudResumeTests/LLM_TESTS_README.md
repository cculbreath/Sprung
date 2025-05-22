# LLM Compatibility Tests for PhysCloudResume

This directory contains automated tests for verifying LLM provider compatibility with the `RecommendJobButton` functionality in PhysCloudResume.

## Overview

The tests verify that job recommendations work correctly across multiple LLM providers:
- OpenAI (gpt-4.1, o3, o4-mini)
- Anthropic Claude (claude-3-5-haiku-20241022)
- Grok (grok-3-mini-fast)
- Gemini (gemini-2.0-flash)

## Test Suite Structure

1. **LLMCompatibilityTests**: Directly tests the JobRecommendationProvider with real API calls to each LLM service.
2. **RecommendJobButtonUITests**: Tests the RecommendJobButton UI component and its integration with the JobRecommendationProvider.
3. **TestHelpers**: Provides utility functions for managing API keys and test configuration.

## Running the Tests

### Prerequisites

1. Valid API keys for each provider you want to test
2. Swift and Xcode environment set up to build and run PhysCloudResume

### Using the Test Runner Script

The simplest way to run the tests is using the included script:

```bash
# Set your API keys
export OPENAI_API_KEY="your_openai_api_key"
export ANTHROPIC_API_KEY="your_anthropic_api_key"
export GROK_API_KEY="your_grok_api_key"
export GEMINI_API_KEY="your_gemini_api_key"

# Run the tests
./run_llm_tests.sh
```

The script will:
1. Check which API keys are available
2. Only test the models for which you have valid API keys
3. Run the tests in parallel
4. Provide a detailed report of results

### Running Tests Manually

You can also run tests manually with Swift:

```bash
# Set environment variables
export OPENAI_API_KEY="your_openai_api_key"
export ANTHROPIC_API_KEY="your_anthropic_api_key"
export GROK_API_KEY="your_grok_api_key"
export GEMINI_API_KEY="your_gemini_api_key"

# Run just the LLM compatibility tests
swift test --filter LLMCompatibilityTests

# Run just the UI tests
swift test --filter RecommendJobButtonUITests

# Run all tests
swift test
```

## Expected Results

Based on the CSV analysis, the expected results are:

| Model | Expected Behavior | Notes |
|-------|-------------------|-------|
| gpt-4.1 | Success | Works correctly |
| o3 | Success | Works correctly |
| o4-mini | Failure | Should fail with "reasoning_effort" error |
| grok-3-mini-fast | Success | Works correctly |
| gemini-2.0-flash | Success | Works correctly |
| claude-3-5-haiku-20241022 | Success | Works correctly |

## Troubleshooting

If tests fail, check the following:

1. **API Keys**: Ensure your API keys are valid and have the necessary permissions.
2. **Rate Limits**: If running tests repeatedly, you might hit rate limits.
3. **Network Issues**: Tests require internet connectivity to make API calls.
4. **Model Availability**: Check if the model you're testing is still available from the provider.

## Adding New Models

To add a new model to the test suite:

1. Add the model identifier to the `testModels` array in `LLMCompatibilityTests.swift`
2. Add the expected behavior to the `expectedResults` dictionary
3. Update the test runner script if needed

## Security Notes

- Never commit API keys to version control
- The test runner uses environment variables to minimize the risk of exposing API keys
- API calls will incur charges based on your provider agreements
