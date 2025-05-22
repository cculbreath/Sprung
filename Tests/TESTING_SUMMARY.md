# PhysCloudResume LLM Compatibility Testing Framework

## Summary

This testing framework provides automated verification of the `RecommendJobButton` functionality across multiple LLM providers, including OpenAI, Anthropic Claude, Grok, and Gemini. It accurately implements the requirements specified in the LLM_functionality_status.csv file and provides detailed diagnostics to help identify and address compatibility issues.

## Files Created

1. `/Tests/PhysCloudResumeTests/LLMCompatibilityTests.swift` - Main test suite for verifying provider compatibility with real API calls
2. `/Tests/PhysCloudResumeTests/RecommendJobButtonTests.swift` - Test for the RecommendJobButton component
3. `/Tests/PhysCloudResumeTests/RecommendJobButtonUITests.swift` - UI tests for the button with ViewInspector
4. `/Tests/PhysCloudResumeTests/TestHelpers.swift` - Helper utilities for API key management and test configuration
5. `/Tests/run_llm_tests.sh` - Shell script for running tests with API keys from environment variables
6. `/Tests/PhysCloudResumeTests/LLM_TESTS_README.md` - Documentation for running and extending the tests
7. `/Tests/PhysCloudResumeTests/sample_test_output.txt` - Example test output showing expected results

## Key Features

1. **Parallel Testing**: Tests run multiple LLM models in parallel for efficiency
2. **API Key Management**: Automatically detects available API keys and runs tests only for supported providers
3. **Detailed Reporting**: Provides comprehensive test reports with metrics like response time and success rates
4. **Error Handling**: Properly handles expected errors like the o4-mini "reasoning_effort" issue
5. **Configurable**: Can be customized via environment variables to test specific models
6. **Real API Integration**: Makes actual API calls to verify true compatibility
7. **UI Component Testing**: Tests both the backend provider and the frontend UI component

## Usage

To run the tests:

1. Set your API keys as environment variables:
   ```bash
   export OPENAI_API_KEY="your_openai_api_key"
   export ANTHROPIC_API_KEY="your_anthropic_api_key"
   export GROK_API_KEY="your_grok_api_key"
   export GEMINI_API_KEY="your_gemini_api_key"
   ```

2. Run the test script:
   ```bash
   cd /Users/cculbreath/devlocal/codebase/PhysCloudResume/Tests
   ./run_llm_tests.sh
   ```

3. Alternatively, run the tests directly with Swift:
   ```bash
   swift test --filter LLMCompatibilityTests
   ```

## Expected Results

Based on the CSV file analysis:

| Model | Expected Result | Notes |
|-------|----------------|-------|
| gpt-4.1 | ✅ Pass | Works correctly |
| o3 | ✅ Pass | Works correctly |
| o4-mini | ❌ Fail | Fails with "reasoning_effort" error (expected behavior) |
| grok-3-mini-fast | ✅ Pass | Works correctly |
| gemini-2.0-flash | ✅ Pass | Works correctly |
| claude-3-5-haiku-20241022 | ✅ Pass | Works correctly |

## Next Steps

1. **CI/CD Integration**: Incorporate these tests into your CI/CD pipeline
2. **Test Expansion**: Add tests for other LLM functionality from the CSV
3. **Cross-OS Testing**: Ensure tests work on all development environments 
4. **Monitoring**: Set up regular testing to detect API changes that might break compatibility

## Notes

- Running these tests will make real API calls and may incur charges
- Some tests might timeout or fail if rate limits are exceeded
- The test script adapts to available API keys, so you only need keys for the providers you want to test
