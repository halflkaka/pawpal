import json
import os

from openai import OpenAI

from prompt import SYSTEM_PROMPT
from schemas import AnalyzeRequest, AnalyzeResponse


def analyze_symptoms(request: AnalyzeRequest) -> AnalyzeResponse:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        return fallback_response()

    client = OpenAI(api_key=api_key)

    user_prompt = build_user_prompt(request)

    try:
        response = client.chat.completions.create(
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            temperature=0.2,
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt},
            ],
        )

        content = response.choices[0].message.content or "{}"
        payload = json.loads(content)

        return AnalyzeResponse(
            urgency=normalize_urgency(payload.get("urgency")),
            possibleCauses=clean_list(payload.get("possibleCauses"), fallback=["Unclear symptom pattern"]),
            nextSteps=clean_list(
                payload.get("nextSteps"),
                fallback=["Monitor symptoms closely", "Contact a veterinarian if symptoms worsen"],
            ),
            redFlags=clean_list(
                payload.get("redFlags"),
                fallback=["Trouble breathing", "Repeated vomiting", "Marked low energy"],
            ),
            vetRecommended=bool(payload.get("vetRecommended", True)),
            summary=clean_text(
                payload.get("summary"),
                fallback="A licensed veterinarian should evaluate persistent, worsening, or severe symptoms.",
            ),
        )
    except Exception:
        return fallback_response()


def build_user_prompt(request: AnalyzeRequest) -> str:
    return f"""
Analyze this pet symptom report and return JSON with exactly these keys:
- urgency
- possibleCauses
- nextSteps
- redFlags
- vetRecommended
- summary

Pet profile:
- Name: {request.pet.name or 'Unknown'}
- Species: {request.pet.species or 'Unknown'}
- Breed: {request.pet.breed or 'Unknown'}
- Age: {request.pet.age or 'Unknown'}
- Weight: {request.pet.weight or 'Unknown'}
- Notes: {request.pet.notes or 'None'}

Symptom report:
- Symptoms: {request.symptomText}
- Duration: {request.durationText or 'Unknown'}
- Extra notes: {request.extraNotes or 'None'}

Output requirements:
- urgency must be one of: emergency, soon, monitor
- possibleCauses should have 2 to 4 short items
- nextSteps should have 2 to 4 short items
- redFlags should have 3 to 5 short items
- summary should be concise and safe
- Use plain English
- Avoid certainty
""".strip()


from typing import Optional


def normalize_urgency(value: Optional[str]) -> str:
    if value in {"emergency", "soon", "monitor"}:
        return value
    return "soon"


def clean_list(value, fallback: list[str]) -> list[str]:
    if isinstance(value, list):
        cleaned = [str(item).strip() for item in value if str(item).strip()]
        if cleaned:
            return cleaned[:5]
    return fallback


def clean_text(value, fallback: str) -> str:
    text = str(value).strip() if value is not None else ""
    return text or fallback


def fallback_response() -> AnalyzeResponse:
    return AnalyzeResponse(
        urgency="soon",
        possibleCauses=[
            "Stomach upset or dietary indiscretion",
            "A mild illness or inflammatory issue",
        ],
        nextSteps=[
            "Monitor appetite, water intake, and energy",
            "Avoid giving human medications",
            "Contact a veterinarian if symptoms continue or worsen",
        ],
        redFlags=[
            "Trouble breathing",
            "Repeated vomiting",
            "Severe lethargy",
        ],
        vetRecommended=True,
        summary="A licensed veterinarian should evaluate persistent, worsening, or severe symptoms.",
    )
