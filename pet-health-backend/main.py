from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from ai_service import analyze_symptoms
from schemas import AnalyzeRequest, AnalyzeResponse

app = FastAPI(title="Pet Health Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.post("/analyze", response_model=AnalyzeResponse)
def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
    return analyze_symptoms(request)
