from pydantic import BaseModel


class PetProfile(BaseModel):
    name: str
    species: str
    breed: str
    age: str
    weight: str
    notes: str


class AnalyzeRequest(BaseModel):
    pet: PetProfile
    symptomText: str
    durationText: str
    extraNotes: str


class AnalyzeResponse(BaseModel):
    urgency: str
    possibleCauses: list[str]
    nextSteps: list[str]
    redFlags: list[str]
    vetRecommended: bool
    summary: str
