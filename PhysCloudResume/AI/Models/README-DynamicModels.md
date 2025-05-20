# Dynamic LLM Model Selection

This feature adds dynamic model fetching and selection capabilities to the app, making it easier to use different AI models across providers.

## Recent Updates

- **Added Gemini Support**: Now supporting Google's Gemini models (1.5-pro, 1.5-flash, etc.)
- **Improved Model Filtering**: Enhanced filtering for OpenAI models to intelligently handle "o"-series models
- **Removed Temperature Parameters**: All model API calls now use server-provided defaults instead of hardcoded temperature values.
- **Added Model Filtering**: Models are now intelligently filtered to show only the most relevant options, reducing clutter.

## Key Components

### ModelService

The new `ModelService` class is responsible for:

- Fetching available models from all supported providers (OpenAI, Claude, Grok, Gemini)
- Caching model lists for faster startup
- Providing models sorted by provider
- Tracking the fetch status for each provider
- Filtering models to show only the most relevant versions

### ModelFilters

The `ModelFilters` struct provides intelligent filtering for model lists:

- Keeps only one variant of each model family when possible
- Prioritizes base models over specific versions
- Ensures consistent output across different providers

### ModelPickerView

A reusable SwiftUI component that:

- Shows available models in a picker, grouped by provider
- Supports filtering by provider
- Includes a refresh button to update the model list
- Shows fetch status information

## How It Works

1. When the app starts, the ModelService is created as part of AppState
2. ModelPickerView gets injected into any view that needs model selection
3. When a provider API key is changed, models are automatically fetched
4. Model lists are filtered to show only the most relevant options
5. Model selections are stored in UserDefaults and used throughout the app

## Usage Examples

### In Settings:

The model picker appears in the settings view with a refresh button, allowing users to easily switch between all available models across providers.

### In Review Sheets:

Both the Application Review and Resume Review sheets now include a model picker, letting users select which model to use for the specific review task.

## Benefits

- No more hardcoded model names
- Easier to use newer models as they're released
- Better support for multi-provider workflows
- Graceful fallback when APIs are unavailable
- Cleaner UI with filtered model lists
- More consistent behavior with default temperature settings

## Technical Details

- Models are fetched directly using the available API endpoints for each provider
- Models are filtered to reduce clutter while maintaining full functionality
- Temperature parameters have been made optional throughout the codebase
- When a model is selected, the appropriate client is created for that provider
- If a model call fails, helpful error messages suggest trying a different model

### Provider-Specific Implementations

#### OpenAI
- Endpoint: `https://api.openai.com/v1/models`
- Authorization: Bearer token in header
- Response Format: List of models in `data` array with `id` field

#### Claude
- Endpoint: `https://api.anthropic.com/v1/models`
- Authorization: API key in `x-api-key` header
- Response Format: List of models in `models` array with `id` field

#### Grok/X.AI
- Endpoints: 
  - Groq: `https://api.groq.com/v1/models`
  - X.AI: `https://api.x.ai/v1/models`
- Authorization: Bearer token in header
- Response Format: Similar to OpenAI with `data` array

#### Gemini
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models?key={API_KEY}`
- Authorization: API key in URL parameter
- Response Format: List of models under `models` array with path-style naming
  - Example: `"models/gemini-1.5-pro"` → parsed as `"gemini-1.5-pro"`

## Troubleshooting

If you encounter issues with model selection:

1. Check API keys in Settings
2. Click the refresh button on the model picker
3. Try a different model if a specific one is failing
4. Restart the app if model lists don't appear

### Provider-Specific Issues

#### Gemini
- Ensure API key starts with "AIza" and has at least 20 characters
- Make sure your API key has permission to use Gemini models
- If models aren't loading, the Gemini service will automatically fall back to a default set of models:
  - `gemini-1.5-pro`
  - `gemini-1.5-flash`
  - `gemini-1.0-pro`

#### OpenAI
- API key must start with "sk-" or "sk-proj-" for project-scoped keys
- If no models are returned, check API key permissions

#### Claude
- API key must start with "sk-ant-"
- Claude requires the appropriate versioning header ("anthropic-version": "2023-06-01")

#### Grok
- Supports both Groq API keys (gsk_...) and X.AI API keys (xai-...)

## Future Improvements

- Add better error handling for specific model compatibility issues
- Support model categories (Vision, Reasoning, etc.)
- Add model capability badges to indicate support for images, etc.
- Cache models with expiration dates for better offline support
- Implement proper rate limiting for API calls
- Add more advanced filtering options for specialized models
- Support additional providers like:
  - Groq API (separate from Grok functionality)
  - Cohere 
  - Mistral AI
  - AWS Bedrock models
