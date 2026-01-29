# Image Search Verification Scaffold - Implementation Plan

## Overview
A Python CLI application that searches for images, then uses Claude's vision capabilities to verify the image matches the user's description before returning it.

## Architecture

```
User Input (description)
    ↓
Claude generates optimized search query
    ↓
Google Custom Search API (get image URLs)
    ↓
For each image (up to 20 total):
    ├── Fetch image
    ├── Send to Claude Vision with description
    ├── If match → Return to user
    └── If no match → Try next image
           ↓
    If batch exhausted, fetch more from Google (pagination)
    ↓
Return best match or "no match found" after 20 attempts
```

## Files to Create

### 1. `main.py` - CLI entry point
- Argument parsing (image description)
- Main search-verify loop
- Output formatting

### 2. `query_generator.py` - LLM-based search query generation
- `generate_search_query(description: str) -> str`
- Uses Claude to convert natural description into optimized image search terms

### 3. `image_search.py` - Google Custom Search integration
- `search_images(query: str, start_index: int) -> list[str]`
- Returns list of image URLs with pagination support

### 4. `image_verifier.py` - Claude Vision verification
- `verify_image(image_url: str, description: str) -> tuple[bool, str]`
- Fetches image, sends to Claude, returns (match, explanation)

### 5. `requirements.txt` - Dependencies
- `anthropic` - Claude API
- `requests` - HTTP requests
- `python-dotenv` - Environment variables

## Implementation Details

### Google Custom Search Setup
User will need to:
1. Create a Custom Search Engine at https://cse.google.com/
2. Enable "Image search" in the CSE settings
3. Get API key from Google Cloud Console
4. Add to `.env`: `GOOGLE_API_KEY` and `GOOGLE_CSE_ID`

### Query Generation Prompt
```
"Convert this image description into an optimized Google Image search query.
Keep it concise (3-6 words). Focus on key visual elements.

Description: {user_description}

Return ONLY the search query, nothing else."
```

### Verification Prompt Strategy
```
"Does this image match the following description?
Description: {user_description}

Answer with YES or NO, followed by a brief explanation."
```

### Search Loop Logic (with pagination)
1. Generate optimized search query via Claude
2. Fetch first batch of 10 images from Google
3. For each image:
   - Fetch and verify with Claude Vision
   - If YES → display URL and exit
   - If NO → continue to next
4. If batch exhausted and under 20 total checked:
   - Fetch next batch (start_index += 10)
   - Continue verification
5. After 20 images checked → report no match found

### Configurable Limit
- `MAX_IMAGES = 20` (can be adjusted in main.py)

## Environment Variables Required
```
ANTHROPIC_API_KEY=... (already present)
GOOGLE_API_KEY=...
GOOGLE_CSE_ID=...
```

## Verification / Testing
1. Run `pip install -r requirements.txt`
2. Set up Google Custom Search credentials in `.env`
3. Test with: `python main.py "a red sports car on a mountain road"`
4. Verify the returned image actually matches the description
