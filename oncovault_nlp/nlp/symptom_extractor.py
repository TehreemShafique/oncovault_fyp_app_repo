import re
from typing import Dict, List, Optional
from models.request_response import SymptomItem

SYMPTOM_PATTERNS = {
    "shortnessOfBreath": [
        r"\b(?:shortness of breath|dyspnea|breathlessness|difficulty breathing|sob)\b",
    ],
    "bonePain": [
        r"\b(?:bone pain|joint pain|bone ache|arthralgia|skeletal pain|bone tenderness|sternal pain|bone aches)\b",
    ],
    "fever": [
        r"\b(?:fever|febrile|pyrexia|high temperature|elevated temperature|fevers)\b",
    ],
    "familyHistory": [
        r"\b(?:family history of (?:leukemia|cancer|blood cancer|lymphoma|hematologic disorders?)|family history)\b",
        r"\b(?:mother|father|sister|brother|parent|grandmother|grandfather)\s+(?:had|has|diagnosed with)\s+(?:leukemia|lymphoma|cancer|blood cancer)\b",
    ],
    "frequentInfections": [
        r"\b(?:frequent infections?|recurrent infections?|repeated infections?|susceptibility to infections?|chronic infections?)\b",
    ],
    "itchySkinOrRash": [
        r"\b(?:itchy skin|skin rash|pruritus|itching|cutaneous rash|petechial rash|skin lesions?|dermatitis)\b",
    ],
    "lossOfAppetiteOrNausea": [
        r"\b(?:loss of appetite|decreased appetite|anorexia|nausea|vomiting|poor oral intake|nauseous)\b",
    ],
    "persistentWeaknessAndFatigue": [
        r"\b(?:persistent (?:weakness and )?fatigue|persistent weakness|fatigue|weakness|lethargy|malaise|exhaustion|tiredness|chronic fatigue|weakness and fatigue)\b",
    ],
    "swollenPainlessLymphNodes": [
        r"\b(?:swollen (?:painless )?lymph nodes|painless lymph nodes|lymphadenopathy|enlarged lymph nodes|swollen glands|cervical lymphadenopathy|axillary lymphadenopathy|inguinal lymphadenopathy)\b",
    ],
    "significantBruisingOrBleeding": [
        r"\b(?:significant bruising or bleeding|easy bruising|bruising|bleeding|petechiae|purpura|ecchymosis|gum bleeding|epistaxis|nose bleeds?|unexplained bleeding)\b",
    ],
    "enlargedLiver": [
        r"\b(?:enlarged liver|hepatomegaly|liver enlargement|hepatosplenomegaly|enlarged spleen|splenomegaly)\b",
    ],
    "oralCavityChanges": [
        r"\b(?:oral cavity changes|mouth ulcers?|gingival bleeding|gum swelling|gingival hyperplasia|stomatitis|oral mucositis|mouth sores?)\b",
    ],
    "visionBlurring": [
        r"\b(?:vision blurring|blurred vision|visual changes|blurry vision|diplopia|visual disturbance)\b",
    ],
    "jaundice": [
        r"\b(?:jaundice|icterus|yellowing of (?:the )?skin|scleral icterus|yellow eyes)\b",
    ],
    "nightSweats": [
        r"\b(?:night sweats?|drenching night sweats?|nocturnal diaphoresis|sweating at night)\b",
    ],
    "smokes": [
        r"\b(?:smoker|smoking|tobacco use|smokes cigarettes?|history of smoking|current smoker)\b",
    ],
}

def extract_symptoms_from_text(doc, raw_text: str) -> Dict[str, SymptomItem]:
    symptoms: Dict[str, SymptomItem] = {}
    
    sentences = [sent.text for sent in doc.sents] if hasattr(doc, "sents") else [raw_text]
    if not sentences:
        sentences = [raw_text]
        
    for sent in sentences:
        sent_clean = sent.strip()
        if not sent_clean:
            continue
            
        for sym_key, patterns in SYMPTOM_PATTERNS.items():
            for pat in patterns:
                for match in re.finditer(pat, sent_clean, re.IGNORECASE):
                    start, end = match.span()
                    matched_phrase = match.group(0)
                    
                    preceding = sent_clean[:start].lower()
                    following = sent_clean[end:].lower()
                    
                    # Check context / negation
                    status = "present"
                    value = True
                    
                    # Family check
                    is_family = False
                    if sym_key != "familyHistory":
                        if re.search(r"\b(?:mother|father|sister|brother|parent|parents|grandmother|grandfather|uncle|aunt|cousin|family)\b", preceding):
                            is_family = True
                            status = "family_history"
                            value = False
                    
                    # Negation check
                    # Check preceding negation words within the clause
                    neg_match = re.search(r"\b(?:denies|denied|denying|no|not|without|never|negative for|rules out|no evidence of|no sign of|no complaints of|free of|non)\b", preceding)
                    if neg_match:
                        # Ensure no contrast conjunction between negation and concept
                        between = preceding[neg_match.end():]
                        if not re.search(r"\b(?:but|however|except|although|while|yet)\b", between):
                            status = "negated"
                            value = False
                            
                    if not is_family and status != "negated":
                        # Check immediate following negation like "is ruled out" or "absent"
                        if re.search(r"^\s*(?:is\s+)?(?:absent|ruled out|negative)\b", following):
                            status = "negated"
                            value = False
                            
                    # Construct source span for traceability
                    source_start = max(0, start - 15)
                    source_end = min(len(sent_clean), end + 15)
                    source_text = sent_clean[source_start:source_end].strip()
                    
                    if not is_family or sym_key == "familyHistory":
                        symptoms[sym_key] = SymptomItem(
                            value=value,
                            status=status,
                            source_text=source_text,
                            confidence=0.95
                        )
                        
    return symptoms
