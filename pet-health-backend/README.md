# Pet Health Backend

## Run locally

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
```

Server runs at `http://127.0.0.1:8000`.

## Endpoints

- `GET /health`
- `POST /analyze`

Current version uses simple keyword-based logic as a starter.
You can later replace `ai_service.py` with a real LLM call.
