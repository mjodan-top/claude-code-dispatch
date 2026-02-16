# Prompt Guide for Agent Teams

## Good Prompt Structure

```
[Task description — what to build]

[Tech stack]

[Quality requirements]
- Run and verify output
- Write tests, all must pass
- Handle errors/edge cases

[Project structure (optional)]
```

## Example: Good

```
Build a GitHub Trending CLI tool:

Tech stack: Python 3.10+, requests, beautifulsoup4, Click

Features:
1. Scrape GitHub Trending page
2. Filter by language (--language python)
3. Filter by time range (--since daily/weekly/monthly)
4. Output in JSON and Table formats

Quality requirements:
1. Run a demo to verify output
2. pytest tests (≥5 test cases)
3. Add timeout and retry for network requests
4. Handle parsing failures gracefully

Project structure:
├── gh_trending/
│   ├── cli.py
│   ├── scraper.py
│   └── formatter.py
├── tests/
│   └── test_scraper.py
├── requirements.txt
└── README.md
```

## Example: Bad

```
# ❌ Too vague
Write a scraper

# ❌ No quality requirements
Write an API

# ❌ No tech stack
Build a TODO app
```

## Advanced Prompt Techniques

### Force Test Coverage
```
Test requirements:
- Coverage >= 80%
- Normal paths + error paths
- Mock all external dependencies
```

### Force Code Style
```
Code standards:
- All functions have docstrings
- Use type hints
- ruff check with zero lint errors
```

### Force Specific Architecture
```
Architecture requirements:
- Layered design (controller / service / repository)
- Dependency injection
- Configuration via environment variables
```

## Token Efficiency Tips

- Be specific about what you want — vague prompts waste exploration tokens
- Include project structure — reduces Lead's planning overhead
- Specify tech stack — prevents framework selection debate
- Set clear "done" criteria — prevents over-engineering
