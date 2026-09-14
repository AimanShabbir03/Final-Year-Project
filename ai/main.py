from __future__ import annotations

import os
import logging
from typing import Literal

from fastapi import FastAPI
from fastapi import HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import stripe
from dotenv import load_dotenv

try:
    from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
except Exception:
    SentimentIntensityAnalyzer = None


app = FastAPI(title="Sentiment Service", version="1.0.0")
logger = logging.getLogger("stripe_payment")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

load_dotenv()

_analyzer = SentimentIntensityAnalyzer() if SentimentIntensityAnalyzer else None

stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
_stripe_secret_key = (stripe.api_key or "").strip()
if _stripe_secret_key:
    stripe.api_key = _stripe_secret_key


class SentimentRequest(BaseModel):
    text: str = Field(..., min_length=1, description="Comment text")


class SentimentResponse(BaseModel):
    sentiment: Literal["positive", "neutral", "negative"]


class CreatePaymentIntentRequest(BaseModel):
    amount: float = Field(..., gt=0, description="Ride fare in major currency units")
    rideId: str = Field(..., min_length=1)
    parentId: str = Field(..., min_length=1)


class CreatePaymentIntentResponse(BaseModel):
    client_secret: str
    payment_intent_id: str


class CreateSalaryPaymentIntentRequest(BaseModel):
    amount: float = Field(..., gt=0, description="Salary amount in major currency units")
    adminId: str = Field(..., min_length=1)
    superAdminId: str = Field(..., min_length=1)
    monthKey: str = Field(..., min_length=1)


def _label_from_score(score: float) -> Literal["positive", "neutral", "negative"]:
    if score > 0.05:
        return "positive"
    if score < -0.05:
        return "negative"
    return "neutral"


def _has_negative_context(text: str) -> bool:
    lower_text = text.lower()
    negative_context_tokens = [
        "not",
        "no",
        "never",
        "didn't",
        "didnt",
        "cannot",
        "can't",
        "cant",
        "won't",
        "wont",
        "isn't",
        "isnt",
        "wasn't",
        "wasnt",
        "aren't",
        "arent",
        "don't",
        "dont",
    ]
    return any(token in lower_text for token in negative_context_tokens)


def _classify_vader_with_overrides(
    text: str,
    score: float,
) -> Literal["positive", "neutral", "negative"]:
    lower_text = text.lower()

    if score <= -0.15:
        return "negative"

    negative_phrases = [
        "late",
        "not reliable",
        "not good",
        "poor",
        "bad",
        "unsafe",
        "not satisfied",
        "communication issue",
    ]
    strong_positive_phrases = [
        "very satisfied",
        "excellent",
        "great service",
        "polite",
        "safe",
        "on time",
        "highly satisfied",
    ]
    neutral_indicators = [
        "room for improvement",
        "okay",
        "average",
        "acceptable",
        "met expectations",
        "nothing unusual",
        "completed normally",
        "completed",
        "expected",
        "normal",
        "successfully",
    ]

    has_negative_phrase = any(phrase in lower_text for phrase in negative_phrases)
    has_strong_positive = any(
        phrase in lower_text for phrase in strong_positive_phrases
    )
    has_neutral_indicator = any(
        phrase in lower_text for phrase in neutral_indicators
    )

    if has_negative_phrase and _has_negative_context(lower_text):
        return "negative"

    # Keep strong positive detection for clearly appreciative wording.
    if has_strong_positive and score > -0.05:
        return "positive"

    # Force neutral for "okay/average/met expectations" style feedback
    # when no strong positive phrase is present.
    if has_neutral_indicator and not has_strong_positive:
        return "neutral"

    if score >= 0.05:
        return "positive"

    return "neutral"


def _fallback_compound_score(text: str) -> float:
    positive_words = {
        "good",
        "great",
        "excellent",
        "nice",
        "polite",
        "safe",
        "friendly",
        "best",
        "amazing",
        "love",
        "helpful",
        "smooth",
        "professional",
    }
    negative_words = {
        "bad",
        "late",
        "rude",
        "unsafe",
        "worst",
        "poor",
        "terrible",
        "slow",
        "angry",
        "hate",
        "delay",
        "unprofessional",
    }

    tokens = [token.strip(".,!?;:()[]{}\"'").lower() for token in text.split()]
    tokens = [t for t in tokens if t]
    if not tokens:
        return 0.0

    score = 0
    for token in tokens:
        if token in positive_words:
            score += 1
        elif token in negative_words:
            score -= 1

    # Normalize into a compact range similar to compound behavior.
    return score / max(len(tokens), 1)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/sentiment", response_model=SentimentResponse)
def sentiment(payload: SentimentRequest) -> SentimentResponse:
    text = payload.text.strip()

    if _analyzer is not None:
        compound = float(_analyzer.polarity_scores(text)["compound"])
        sentiment_label = _classify_vader_with_overrides(text, compound)
    else:
        compound = _fallback_compound_score(text)
        # Keep fallback behavior unchanged.
        sentiment_label = _label_from_score(compound)

    return SentimentResponse(sentiment=sentiment_label)


@app.post("/create-payment-intent", response_model=CreatePaymentIntentResponse)
def create_payment_intent(payload: CreatePaymentIntentRequest) -> CreatePaymentIntentResponse:
    stripe_key = (os.getenv("STRIPE_SECRET_KEY") or "").strip()
    if not stripe_key:
        logger.error("Missing STRIPE_SECRET_KEY for create-payment-intent")
        raise HTTPException(
            status_code=500,
            detail="Stripe secret key is not configured on server.",
        )
    stripe.api_key = stripe_key

    try:
        amount_in_smallest_unit = int(payload.amount * 100)
        if amount_in_smallest_unit <= 0:
            raise HTTPException(status_code=400, detail="Invalid amount.")
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Amount conversion failed in create-payment-intent")
        raise HTTPException(status_code=500, detail=str(e)) from e

    try:
        intent = stripe.PaymentIntent.create(
            amount=amount_in_smallest_unit,
            currency="pkr",
            metadata={
                "rideId": payload.rideId,
                "parentId": payload.parentId,
            },
            automatic_payment_methods={"enabled": True},
        )
    except Exception as e:
        logger.exception("Stripe PaymentIntent creation failed")
        raise HTTPException(
            status_code=500,
            detail=str(e),
        ) from e

    client_secret = getattr(intent, "client_secret", None)
    intent_id = getattr(intent, "id", None)
    if not client_secret or not intent_id:
        logger.error("Stripe intent missing client_secret or id")
        raise HTTPException(
            status_code=500,
            detail="Unable to create payment intent.",
        )

    return CreatePaymentIntentResponse(
        client_secret=client_secret,
        payment_intent_id=intent_id,
    )


@app.post(
    "/create-admin-salary-payment-intent",
    response_model=CreatePaymentIntentResponse,
)
def create_admin_salary_payment_intent(
    payload: CreateSalaryPaymentIntentRequest,
) -> CreatePaymentIntentResponse:
    stripe_key = (os.getenv("STRIPE_SECRET_KEY") or "").strip()
    if not stripe_key:
        logger.error("Missing STRIPE_SECRET_KEY for salary payment intent")
        raise HTTPException(
            status_code=500,
            detail="Stripe secret key is not configured on server.",
        )
    stripe.api_key = stripe_key

    try:
        amount_in_smallest_unit = int(payload.amount * 100)
        if amount_in_smallest_unit <= 0:
            raise HTTPException(status_code=400, detail="Invalid amount.")
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Amount conversion failed in salary payment intent")
        raise HTTPException(status_code=500, detail=str(e)) from e

    try:
        intent = stripe.PaymentIntent.create(
            amount=amount_in_smallest_unit,
            currency="pkr",
            metadata={
                "type": "admin_salary",
                "adminId": payload.adminId,
                "superAdminId": payload.superAdminId,
                "monthKey": payload.monthKey,
            },
            automatic_payment_methods={"enabled": True},
        )
    except Exception as e:
        logger.exception("Stripe salary PaymentIntent creation failed")
        raise HTTPException(
            status_code=500,
            detail=str(e),
        ) from e

    client_secret = getattr(intent, "client_secret", None)
    intent_id = getattr(intent, "id", None)
    if not client_secret or not intent_id:
        logger.error("Stripe salary intent missing client_secret or id")
        raise HTTPException(
            status_code=500,
            detail="Unable to create salary payment intent.",
        )

    return CreatePaymentIntentResponse(
        client_secret=client_secret,
        payment_intent_id=intent_id,
    )
