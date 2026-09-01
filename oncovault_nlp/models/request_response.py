from typing import Optional, Dict, List
from pydantic import BaseModel, Field

class ExtractRequest(BaseModel):
    text: str = Field(..., min_length=1, description='Raw clinical voice transcription text')

class SymptomItem(BaseModel):
    value: bool = Field(..., description='True if present, False if negated')
    status: str = Field(..., description='present, negated, family_history, historical, hypothetical')
    source_text: Optional[str] = Field(None, description='Original text span where concept appeared')
    confidence: Optional[float] = None

class CbcValueItem(BaseModel):
    value: Optional[float] = None
    unit: Optional[str] = None
    status: str = 'present'
    source_text: Optional[str] = None

class DifferentialCountItem(BaseModel):
    absolute: Optional[float] = None
    percentage: Optional[float] = None
    source_text: Optional[str] = None

class CbcExtraction(BaseModel):
    wbc: Optional[CbcValueItem] = None
    rbc: Optional[CbcValueItem] = None
    hemoglobin: Optional[CbcValueItem] = None
    hematocrit: Optional[CbcValueItem] = None
    platelets: Optional[CbcValueItem] = None
    neutrophils: Optional[DifferentialCountItem] = None
    lymphocytes: Optional[DifferentialCountItem] = None
    monocytes: Optional[DifferentialCountItem] = None
    eosinophils: Optional[DifferentialCountItem] = None
    basophils: Optional[DifferentialCountItem] = None
    rdwSd: Optional[CbcValueItem] = None
    rdwCv: Optional[CbcValueItem] = None

class OtherClinicalFields(BaseModel):
    diseaseType: Optional[str] = None
    diagnosisSubtype: Optional[str] = None
    stage: Optional[str] = None
    diagnosisStatus: Optional[str] = None
    blastCellPercentage: Optional[float] = None
    boneMarrowBiopsy: Optional[str] = None
    chemotherapy: Optional[str] = None
    medications: List[str] = []
    clinicalNotes: Optional[str] = None

class ExtractResponse(BaseModel):
    text: str
    symptoms: Dict[str, SymptomItem] = {}
    cbc: CbcExtraction = Field(default_factory=CbcExtraction)
    other: OtherClinicalFields = Field(default_factory=OtherClinicalFields)
    warnings: List[str] = []
