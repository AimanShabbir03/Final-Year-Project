# from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

# analyzer = SentimentIntensityAnalyzer()

# review = "Driver was very polite and good"

# result = analyzer.polarity_scores(review)

# compound = result["compound"]

# if compound >= 0.05:
#     sentiment = "Positive"
# elif compound <= -0.05:
#     sentiment = "Negative"
# else:
#     sentiment = "Neutral"

# print("Review:", review)
# print("Score:", compound)
# print("Sentiment:", sentiment)
import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred)

db = firestore.client()

print("🔥 Firebase connected successfully!")

# simple test: list collections
collections = db.collections()

for col in collections:
    print("Collection found:", col.id)