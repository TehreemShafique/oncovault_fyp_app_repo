import re
from typing import Optional

def normalize_text(text: str) -> str:
    if not text:
        return ""
    text = re.sub(r"\s+", " ", text)
    return text.strip()

def clean_unit(unit_str: Optional[str]) -> Optional[str]:
    if not unit_str:
        return None
    u = unit_str.strip().lower()
    if u in ["k/ul", "k/microl", "k/ul", "10^3/ul", "thousand/ul", "k"]:
        return "k/uL"
    if u in ["g/dl", "gm/dl"]:
        return "g/dL"
    if u in ["m/ul", "mil/ul", "10^6/ul", "m/ul"]:
        return "M/uL"
    if u in ["%", "percent", "pct"]:
        return "%"
    if u in ["fl"]:
        return "fL"
    return unit_str.strip()
