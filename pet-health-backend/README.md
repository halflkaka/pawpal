# Pet Health Backend

## Run locally

```bash
cd pet-health-backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# then put your real OPENAI_API_KEY into .env or export it in your shell
export OPENAI_API_KEY=your_key_here
uvicorn main:app --reload
```

Server runs at `http://127.0.0.1:8000`.

## Endpoints

- `GET /health`
- `POST /analyze`

## Notes

- Current version uses the OpenAI API for analysis.
- If `OPENAI_API_KEY` is missing or the API call fails, the backend falls back to a safe generic response.
- Default model is `gpt-4o-mini`.
- You can override the model with `OPENAI_MODEL`.
