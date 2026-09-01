import re
from typing import Tuple

NEGATION_PATTERNS = [
    r"\b(?:denies|denied|denying)\b",
    r"\b(?:no|not|non|without|never|free of)\b",
    r"\b(?:negative for|rules out|ruled out)\b",
    r"\b(?:no evidence of|no sign of|no complaints of)\b",
    r"\b(?:absence of|unremarkable for)\b",
]

FAMILY_PATTERNS = [
    r"\b(?:mother|father|sister|brother|parent|parents|grandmother|grandfather|uncle|aunt|cousin|family|maternal|paternal)\b",
    r"\b(?:family history of|family member with)\b",
]

HISTORICAL_PATTERNS = [
    r"\b(?:previously|history of|in the past|resolved|in remission|prior history|former)\b",
]

def check_context(sentence_text: str, match_start: int, match_end: int) -> str:
    preceding = sentence_text[:match_start].lower()
    following = sentence_text[match_end:].lower()
    
    # Check negation
    for pat in NEGATION_PATTERNS:
        if re.search(pat, preceding):
            # Check if there is a contrast conjunction between negation and concept
            contrast = re.search(r"\b(?:but|however|except|although)\b", preceding)
            if not contrast or re.search(pat, preceding[contrast.end():]):
                return "negated"
        if re.search(pat, following[:20]):
            return "negated"
            
    # Check family context
    for pat in FAMILY_PATTERNS:
        if re.search(pat, preceding):
            return "family_history"
            
    # Check historical
    for pat in HISTORICAL_PATTERNS:
        if re.search(pat, preceding):
            return "historical"
            
    return "present"
