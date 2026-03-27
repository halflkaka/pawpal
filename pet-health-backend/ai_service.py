from schemas import AnalyzeRequest, AnalyzeResponse


def analyze_symptoms(request: AnalyzeRequest) -> AnalyzeResponse:
    symptom_blob = " ".join(
        [request.symptomText.lower(), request.durationText.lower(), request.extraNotes.lower()]
    )

    emergency_keywords = [
        "trouble breathing",
        "can’t breathe",
        "cannot breathe",
        "seizure",
        "collapsed",
        "collapse",
        "unresponsive",
        "poison",
        "toxin",
        "bloated abdomen",
        "can’t pee",
        "cannot pee",
        "unable to urinate",
        "severe bleeding",
    ]

    soon_keywords = [
        "vomit",
        "vomiting",
        "diarrhea",
        "not eating",
        "lethargic",
        "lethargy",
        "limping",
        "pain",
        "coughing",
        "ear infection",
        "eye discharge",
    ]

    if any(keyword in symptom_blob for keyword in emergency_keywords):
        return AnalyzeResponse(
            urgency="emergency",
            possibleCauses=[
                "A potentially serious medical issue",
                "A condition needing urgent veterinary evaluation",
            ],
            nextSteps=[
                "Seek emergency veterinary care now",
                "Keep your pet calm and transport safely",
                "Do not wait for symptoms to resolve on their own",
            ],
            redFlags=[
                "Breathing difficulty",
                "Collapse or unresponsiveness",
                "Possible toxin exposure",
            ],
            vetRecommended=True,
            summary="These symptoms may indicate an emergency. Your pet should be evaluated by a veterinarian immediately.",
        )

    if any(keyword in symptom_blob for keyword in soon_keywords):
        return AnalyzeResponse(
            urgency="soon",
            possibleCauses=[
                "Stomach upset or dietary indiscretion",
                "An early infection or inflammatory problem",
                "Another non-specific illness needing monitoring",
            ],
            nextSteps=[
                "Monitor appetite, water intake, and energy",
                "Avoid giving human medications",
                "Arrange a veterinary visit soon if symptoms continue or worsen",
            ],
            redFlags=[
                "Repeated vomiting or diarrhea",
                "Trouble breathing",
                "Severe lethargy",
                "Pain that is worsening",
            ],
            vetRecommended=True,
            summary="This may not be an emergency right now, but the symptoms suggest your pet should be watched closely and seen by a veterinarian if not improving.",
        )

    return AnalyzeResponse(
        urgency="monitor",
        possibleCauses=[
            "A mild self-limited issue",
            "Minor irritation or temporary stomach upset",
        ],
        nextSteps=[
            "Monitor symptoms closely",
            "Keep notes on any changes",
            "Contact a veterinarian if symptoms worsen or persist",
        ],
        redFlags=[
            "Trouble breathing",
            "Repeated vomiting",
            "Marked low energy",
        ],
        vetRecommended=False,
        summary="This may be mild, but continued monitoring is important. A licensed veterinarian should evaluate any worsening symptoms.",
    )
