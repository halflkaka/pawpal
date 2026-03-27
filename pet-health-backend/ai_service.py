import json
import os
from typing import Optional

from openai import OpenAI

from prompt import SYSTEM_PROMPT
from schemas import AnalyzeRequest, AnalyzeResponse

EMERGENCY_KEYWORDS = [
    "trouble breathing",
    "difficulty breathing",
    "can't breathe",
    "cannot breathe",
    "seizure",
    "seizing",
    "collapsed",
    "collapse",
    "unresponsive",
    "not waking up",
    "poison",
    "poisoning",
    "toxin",
    "ate chocolate",
    "ate grapes",
    "bloated abdomen",
    "distended abdomen",
    "unable to urinate",
    "can't pee",
    "cannot pee",
    "severe bleeding",
    "hit by car",
    "pale gums",
]

HIGH_PRIORITY_KEYWORDS = [
    "vomiting",
    "vomit",
    "diarrhea",
    "lethargy",
    "lethargic",
    "not eating",
    "won't eat",
    "limping",
    "pain",
    "coughing",
    "eye discharge",
    "ear infection",
    "itchy skin",
    "licking paws",
]


def analyze_symptoms(request: AnalyzeRequest) -> AnalyzeResponse:
    emergency = emergency_override(request)
    if emergency is not None:
        return emergency

    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        return fallback_response(request)

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
        urgency = normalize_urgency(payload.get("urgency"), request)

        return AnalyzeResponse(
            urgency=urgency,
            possibleCauses=clean_list(
                payload.get("possibleCauses"),
                fallback=fallback_possible_causes(request, urgency),
            ),
            nextSteps=clean_list(
                payload.get("nextSteps"),
                fallback=fallback_next_steps(urgency),
            ),
            redFlags=clean_list(
                payload.get("redFlags"),
                fallback=default_red_flags(urgency),
            ),
            vetRecommended=urgency != "monitor" or bool(payload.get("vetRecommended", False)),
            summary=clean_text(
                payload.get("summary"),
                fallback=fallback_summary(urgency),
            ),
        )
    except Exception:
        return fallback_response(request)


def emergency_override(request: AnalyzeRequest) -> Optional[AnalyzeResponse]:
    blob = symptom_blob(request)
    if any(keyword in blob for keyword in EMERGENCY_KEYWORDS):
        return AnalyzeResponse(
            urgency="emergency",
            possibleCauses=[
                "A potentially serious medical problem",
                "A condition needing urgent veterinary evaluation",
            ],
            nextSteps=[
                "Seek emergency veterinary care now",
                "Keep your pet calm and transport safely",
                "Do not wait for symptoms to improve on their own",
            ],
            redFlags=[
                "Trouble breathing",
                "Collapse or unresponsiveness",
                "Possible toxin exposure",
                "Unable to urinate",
            ],
            vetRecommended=True,
            summary="These symptoms may indicate an emergency. Your pet should be evaluated by a veterinarian immediately.",
        )
    return None


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
- If symptoms are mild or nonspecific, monitor may be appropriate
- If symptoms are persistent, worsening, painful, or concerning, prefer soon
- If symptoms sound unstable or life-threatening, use emergency
""".strip()


def symptom_blob(request: AnalyzeRequest) -> str:
    return " ".join(
        [
            request.symptomText.lower(),
            request.durationText.lower(),
            request.extraNotes.lower(),
            request.pet.notes.lower(),
        ]
    )


def normalize_urgency(value: Optional[str], request: AnalyzeRequest) -> str:
    if value in {"emergency", "soon", "monitor"}:
        return value

    blob = symptom_blob(request)
    if any(keyword in blob for keyword in HIGH_PRIORITY_KEYWORDS):
        return "soon"
    return "monitor"


def clean_list(value, fallback: list[str]) -> list[str]:
    if isinstance(value, list):
        cleaned = [str(item).strip() for item in value if str(item).strip()]
        if cleaned:
            return cleaned[:5]
    return fallback


def clean_text(value, fallback: str) -> str:
    text = str(value).strip() if value is not None else ""
    return text or fallback


def fallback_possible_causes(request: AnalyzeRequest, urgency: str) -> list[str]:
    blob = symptom_blob(request)
    if "itch" in blob or "licking paws" in blob:
        return [
            "Skin irritation or allergies",
            "An ear, skin, or paw issue causing discomfort",
        ]
    if "vomit" in blob or "diarrhea" in blob:
        return [
            "Stomach upset or dietary indiscretion",
            "A mild gastrointestinal illness",
        ]
    if urgency == "monitor":
        return [
            "A mild self-limited issue",
            "Minor irritation or temporary discomfort",
        ]
    return [
        "A mild illness or inflammatory issue",
        "Another non-specific problem needing monitoring",
    ]


def fallback_next_steps(urgency: str) -> list[str]:
    if urgency == "emergency":
        return [
            "Seek emergency veterinary care now",
            "Keep your pet calm during transport",
            "Do not delay care if symptoms persist",
        ]
    if urgency == "monitor":
        return [
            "Monitor symptoms closely",
            "Keep notes on any changes",
            "Contact a veterinarian if symptoms worsen or persist",
        ]
    return [
        "Monitor appetite, water intake, and energy",
        "Avoid giving human medications",
        "Contact a veterinarian if symptoms continue or worsen",
    ]


def default_red_flags(urgency: str) -> list[str]:
    if urgency == "emergency":
        return [
            "Trouble breathing",
            "Collapse",
            "Unresponsiveness",
            "Possible toxin exposure",
        ]
    return [
        "Trouble breathing",
        "Repeated vomiting",
        "Severe lethargy",
        "Pain that is worsening",
    ]


def fallback_summary(urgency: str) -> str:
    if urgency == "emergency":
        return "These symptoms may indicate an emergency and should be evaluated by a veterinarian immediately."
    if urgency == "monitor":
        return "This may be mild, but continued monitoring is important. A licensed veterinarian should evaluate worsening or persistent symptoms."
    return "This does not clearly sound like an emergency, but a licensed veterinarian should evaluate persistent, worsening, or severe symptoms."


def fallback_response(request: AnalyzeRequest) -> AnalyzeResponse:
    urgency = normalize_urgency(None, request)
    return AnalyzeResponse(
        urgency=urgency,
        possibleCauses=fallback_possible_causes(request, urgency),
        nextSteps=fallback_next_steps(urgency),
        redFlags=default_red_flags(urgency),
        vetRecommended=urgency != "monitor",
        summary=fallback_summary(urgency),
    )
