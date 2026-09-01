import re
from typing import Optional, Tuple
from models.request_response import CbcExtraction, CbcValueItem, DifferentialCountItem
from .normalizer import clean_unit

CBC_PATTERNS = {
    "wbc": [
        r"\b(?:wbc|white blood cell count|white blood cells?|white count|total leukocyte count|tlc)\b",
    ],
    "rbc": [
        r"\b(?:rbc|red blood cell count|red blood cells?|erythrocyte count|erythrocytes)\b",
    ],
    "hemoglobin": [
        r"\b(?:hemoglobin|hgb|hb)\b",
    ],
    "hematocrit": [
        r"\b(?:hematocrit|hct|packed cell volume|pcv)\b",
    ],
    "platelets": [
        r"\b(?:platelets?|plt|platelet count|thrombocytes?)\b",
    ],
    "neutrophils": [
        r"\b(?:neutrophils?|neutrophil count|anc|absolute neutrophil count|polys|segs)\b",
    ],
    "lymphocytes": [
        r"\b(?:lymphocytes?|lymphocyte count|alc|absolute lymphocyte count|lymphs)\b",
    ],
    "monocytes": [
        r"\b(?:monocytes?|monocyte count|amc|absolute monocyte count|monos)\b",
    ],
    "eosinophils": [
        r"\b(?:eosinophils?|eosinophil count|aec|absolute eosinophil count|eos)\b",
    ],
    "basophils": [
        r"\b(?:basophils?|basophil count|basos)\b",
    ],
    "rdwSd": [
        r"\b(?:rdw-sd|rdw sd)\b",
    ],
    "rdwCv": [
        r"\b(?:rdw-cv|rdw cv|rdw)\b",
    ],
}

def _extract_number_and_unit(following_text: str) -> Tuple[Optional[float], Optional[str], Optional[str]]:
    # Match numbers e.g. "is 14.5 k/uL", "= 10.2 g/dL", "110", "at 65 percent", "3.2 k/uL (65%)"
    match = re.search(
        r"^(?:\s*(?:is|was|of|:|level is|count is|=|\bstands at\b|\baround\b|\bat\b))?\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z/%^0-9]+)?",
        following_text,
        re.IGNORECASE
    )
    if match:
        val_str = match.group(1)
        unit_str = match.group(2) if match.group(2) else None
        full_span = match.group(0).strip()
        try:
            return float(val_str), clean_unit(unit_str), full_span
        except ValueError:
            return None, None, None
    return None, None, None

def extract_cbc_from_text(doc, raw_text: str) -> CbcExtraction:
    cbc = CbcExtraction()
    
    sentences = [sent.text for sent in doc.sents] if hasattr(doc, "sents") else [raw_text]
    if not sentences:
        sentences = [raw_text]
        
    for sent in sentences:
        sent_clean = sent.strip()
        if not sent_clean:
            continue
            
        for param, patterns in CBC_PATTERNS.items():
            for pat in patterns:
                for match in re.finditer(pat, sent_clean, re.IGNORECASE):
                    start, end = match.span()
                    matched_param = match.group(0)
                    following = sent_clean[end:]
                    
                    val, unit, span = _extract_number_and_unit(following)
                    if val is None:
                        continue
                        
                    source_text = f"{matched_param} {span}".strip()
                    
                    if param in ["neutrophils", "lymphocytes", "monocytes", "eosinophils", "basophils"]:
                        # Differential: check if percentage or absolute
                        is_pct = False
                        if unit == "%" or "percent" in following[:15].lower() or val > 15.0 and (not unit or unit == "%"):
                            is_pct = True
                        if "anc" in matched_param.lower() or "alc" in matched_param.lower() or "amc" in matched_param.lower() or "aec" in matched_param.lower():
                            is_pct = False
                            
                        diff_item = getattr(cbc, param) or DifferentialCountItem()
                        if is_pct:
                            diff_item.percentage = val
                        else:
                            diff_item.absolute = val
                        diff_item.source_text = source_text
                        setattr(cbc, param, diff_item)
                    else:
                        default_unit = None
                        if param in ["wbc", "platelets"]:
                            default_unit = "k/uL"
                        elif param == "hemoglobin":
                            default_unit = "g/dL"
                        elif param == "rbc":
                            default_unit = "M/uL"
                        elif param == "hematocrit" or param == "rdwCv":
                            default_unit = "%"
                        elif param == "rdwSd":
                            default_unit = "fL"
                            
                        final_unit = unit or default_unit
                        val_item = CbcValueItem(
                            value=val,
                            unit=final_unit,
                            status="present",
                            source_text=source_text
                        )
                        setattr(cbc, param, val_item)
                        
    return cbc
