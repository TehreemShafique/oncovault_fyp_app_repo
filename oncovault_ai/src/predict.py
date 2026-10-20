"""
OncoVault AI Engine - Inference Service
Provides dynamic, patient-specific inference and explainability:
  - Symptom Risk Assessment (leukemia-symptom-v1)
  - CBC Risk Assessment (leukemia-cbc-v1)
Strictly derives all explanations and risk factors dynamically from patient EHR inputs.
"""
import os
import json
import joblib
import numpy as np
from typing import Dict, Any, List, Optional
from datetime import datetime, timezone

from .feature_mapping import (
    SYMPTOM_KEYS, SYMPTOM_LABELS,
    CBC_KEYS, CBC_LABELS, CBC_UNITS
)

class DiagnosticEngine:
    _instance: Optional['DiagnosticEngine'] = None
    
    def __init__(self, models_root: str = "oncovault_ai/models"):
        if not os.path.exists(models_root):
            pkg_models = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "models"))
            if os.path.exists(pkg_models):
                models_root = pkg_models
        self.models_root = models_root
        self.symptom_model = None
        self.symptom_metadata = {}
        self.symptom_feature_importance = []
        
        self.cbc_model = None
        self.cbc_scaler = None
        self.cbc_metadata = {}
        self.cbc_feature_importance = []
        
        self._load_models()
        
    @classmethod
    def get_instance(cls, models_root: str = "oncovault_ai/models") -> 'DiagnosticEngine':
        if cls._instance is None:
            cls._instance = cls(models_root=models_root)
        return cls._instance

    def _load_models(self):
        # 1. Load Symptom Model
        symptom_dir = os.path.join(self.models_root, "leukemia_symptom_v1")
        if os.path.exists(symptom_dir):
            model_path = os.path.join(symptom_dir, "model.joblib")
            meta_path = os.path.join(symptom_dir, "metadata.json")
            feat_path = os.path.join(symptom_dir, "feature_importance.json")
            
            if os.path.exists(model_path):
                self.symptom_model = joblib.load(model_path)
            if os.path.exists(meta_path):
                with open(meta_path, "r", encoding="utf-8") as f:
                    self.symptom_metadata = json.load(f)
            if os.path.exists(feat_path):
                with open(feat_path, "r", encoding="utf-8") as f:
                    self.symptom_feature_importance = json.load(f)
                    
        # 2. Load CBC Model
        cbc_dir = os.path.join(self.models_root, "leukemia_cbc_v1")
        if os.path.exists(cbc_dir):
            model_path = os.path.join(cbc_dir, "model.joblib")
            scaler_path = os.path.join(cbc_dir, "scaler.joblib")
            meta_path = os.path.join(cbc_dir, "metadata.json")
            feat_path = os.path.join(cbc_dir, "feature_importance.json")
            
            if os.path.exists(model_path):
                self.cbc_model = joblib.load(model_path)
            if os.path.exists(scaler_path):
                self.cbc_scaler = joblib.load(scaler_path)
            if os.path.exists(meta_path):
                with open(meta_path, "r", encoding="utf-8") as f:
                    self.cbc_metadata = json.load(f)
            if os.path.exists(feat_path):
                with open(feat_path, "r", encoding="utf-8") as f:
                    self.cbc_feature_importance = json.load(f)

    def assess_symptoms(self, symptoms_input: Dict[str, Any]) -> Dict[str, Any]:
        """
        Calculates symptom-based leukemia risk score and identifies ONLY the actual
        present symptoms in this patient's EHR, ranked by the trained model's feature importance.
        """
        if self.symptom_model is None:
            raise RuntimeError("Symptom model 'leukemia_symptom_v1' is not loaded.")
            
        feature_vector = []
        present_symptoms = set()
        
        for k in SYMPTOM_KEYS:
            val = symptoms_input.get(k, 0)
            if isinstance(val, bool):
                num_val = 1.0 if val else 0.0
            else:
                try:
                    num_val = float(val) if val is not None else 0.0
                except (ValueError, TypeError):
                    num_val = 0.0
            feature_vector.append(num_val)
            if num_val > 0.5:
                present_symptoms.add(k)
                
        X = np.array([feature_vector], dtype=np.float32)
        prob = float(self.symptom_model.predict_proba(X)[0, 1])
        prediction_label = "Elevated Risk" if prob >= 0.50 else "Lower Risk"
        
        # Contributing factors: strictly only symptoms marked present for THIS patient,
        # ordered by their trained model feature importance
        contributing = []
        for item in self.symptom_feature_importance:
            if item["feature_key"] in present_symptoms:
                contributing.append(item["label"])
                
        if not contributing:
            contributing = ["No high-risk symptoms reported in EHR"]
            
        return {
            "prediction": prediction_label,
            "riskScore": round(prob, 4),
            "modelVersion": self.symptom_metadata.get("model_version", "leukemia-symptom-v1"),
            "contributingFactors": contributing[:5],
            "analyzedAt": datetime.now(timezone.utc).isoformat(),
            "disclaimer": "AI risk assessment is for clinical decision support and is not a definitive medical diagnosis."
        }

    def assess_cbc(self, cbc_input: Dict[str, Any]) -> Dict[str, Any]:
        """
        Calculates CBC-based leukemia risk score.
        Dynamically derives contributing factors ONLY from parameters actually recorded in the EHR.
        """
        if self.cbc_model is None or self.cbc_scaler is None:
            raise RuntimeError("CBC model 'leukemia_cbc_v1' is not loaded.")
            
        raw_dict = {}
        provided_keys = set()
        
        # Mean reference fallback values from training scaler for unrecorded parameters
        scaler_means = dict(zip(CBC_KEYS, self.cbc_scaler.mean_))
        
        aliases = {
            "WBC": ["wbc", "WBC(10^9/L)", "wbcCount"],
            "RBC": ["rbc", "RBC(10^12/L)", "rbcCount"],
            "HGB": ["hgb", "hemoglobin", "Hemoglobin", "HGB(g/L)", "hb"],
            "PLT": ["plt", "platelets", "Platelets", "PLT(10^9/L)", "plateletCount"],
            "NEUT_ABS": ["neut_abs", "NEUT#", "neutrophils_abs", "NEUT#(10^9/L)", "neutroAbs"],
            "NEUT_PCT": ["neut_pct", "NEUT%", "neutrophils_pct", "NEUT%(%)", "neutroPct"],
            "MONO_ABS": ["mono_abs", "MONO#", "monocytes_abs", "MONO#(10^9/L)", "monoAbs"],
            "RDW_SD": ["rdw_sd", "rdwSd", "RDW-SD", "RDW-SD(fL)"],
            "RDW_CV": ["rdw_cv", "rdwCv", "RDW-CV", "RDW-CV(%)"]
        }
        
        for k in CBC_KEYS:
            val = cbc_input.get(k, None)
            if val is None:
                for alias in aliases.get(k, []):
                    if alias in cbc_input and cbc_input[alias] is not None:
                        val = cbc_input[alias]
                        break
            
            if val is not None and str(val).strip() != "" and str(val).strip() != "-":
                try:
                    num_val = float(val)
                    if num_val > 0.0:
                        provided_keys.add(k)
                        raw_dict[k] = num_val
                    else:
                        raw_dict[k] = float(scaler_means.get(k, 0.0))
                except (ValueError, TypeError):
                    raw_dict[k] = float(scaler_means.get(k, 0.0))
            else:
                # Impute missing feature with cohort reference mean
                raw_dict[k] = float(scaler_means.get(k, 0.0))

        # Clinical Normalization for Hemoglobin: if entered in g/dL (< 30), convert to g/L (* 10)
        if "HGB" in provided_keys and 0.0 < raw_dict["HGB"] <= 30.0:
            raw_dict["HGB"] = raw_dict["HGB"] * 10.0

        # Auto-calculate absolute neutrophil if percentage & WBC were recorded
        if "NEUT_PCT" in provided_keys and "WBC" in provided_keys and "NEUT_ABS" not in provided_keys:
            raw_dict["NEUT_ABS"] = (raw_dict["WBC"] * raw_dict["NEUT_PCT"]) / 100.0
            provided_keys.add("NEUT_ABS")

        feature_vector = [raw_dict[k] for k in CBC_KEYS]
        X_raw = np.array([feature_vector], dtype=np.float32)
        X_scaled = self.cbc_scaler.transform(X_raw)
        prob = float(self.cbc_model.predict_proba(X_scaled)[0, 1])
        prediction_label = "Elevated Risk" if prob >= 0.50 else "Lower Risk"
        
        # Determine Patient-Specific Contributing Factors:
        # ONLY include parameters that were ACTUALLY recorded in the EHR and show abnormality
        patient_factors = []
        
        # Platelets
        if "PLT" in provided_keys:
            plt_val = raw_dict["PLT"]
            if plt_val < 100.0:
                patient_factors.append(f"Thrombocytopenia (PLT: {plt_val:g} 10^9/L, ref: 150-450)")
            elif plt_val < 150.0:
                patient_factors.append(f"Borderline Low Platelets (PLT: {plt_val:g} 10^9/L)")
            elif plt_val > 450.0:
                patient_factors.append(f"Thrombocytosis (PLT: {plt_val:g} 10^9/L)")
                
        # White Blood Cells
        if "WBC" in provided_keys:
            wbc_val = raw_dict["WBC"]
            if wbc_val > 25.0:
                patient_factors.append(f"Marked Leukocytosis (WBC: {wbc_val:g} 10^9/L, ref: 4.0-11.0)")
            elif wbc_val > 11.0:
                patient_factors.append(f"Elevated WBC (WBC: {wbc_val:g} 10^9/L)")
            elif wbc_val < 4.0:
                patient_factors.append(f"Leukopenia (WBC: {wbc_val:g} 10^9/L, ref: 4.0-11.0)")
                
        # Hemoglobin
        if "HGB" in provided_keys:
            hgb_val = raw_dict["HGB"]
            hgb_dl = hgb_val / 10.0
            if hgb_dl < 10.0:
                patient_factors.append(f"Significant Anemia (HGB: {hgb_dl:.1f} g/dL, ref: 12.0-17.0)")
            elif hgb_dl < 12.0:
                patient_factors.append(f"Mild Anemia (HGB: {hgb_dl:.1f} g/dL)")
                
        # Red Cell Distribution Width
        if "RDW_SD" in provided_keys and raw_dict["RDW_SD"] > 46.0:
            patient_factors.append(f"Elevated Anisocytosis (RDW-SD: {raw_dict['RDW_SD']:g} fL)")
        elif "RDW_CV" in provided_keys and raw_dict["RDW_CV"] > 15.0:
            patient_factors.append(f"Elevated RDW-CV ({raw_dict['RDW_CV']:g}%)")
            
        # Neutrophils
        if "NEUT_PCT" in provided_keys:
            neut_pct = raw_dict["NEUT_PCT"]
            if neut_pct < 40.0:
                patient_factors.append(f"Neutropenia (NEUT%: {neut_pct:g}%, ref: 40-75%)")
            elif neut_pct > 75.0:
                patient_factors.append(f"Neutrophilia (NEUT%: {neut_pct:g}%)")
                
        # Monocytes
        if "MONO_ABS" in provided_keys:
            mono_val = raw_dict["MONO_ABS"]
            if mono_val > 1.0:
                patient_factors.append(f"Monocytosis (MONO#: {mono_val:g} 10^9/L)")
                
        # RBC
        if "RBC" in provided_keys and raw_dict["RBC"] < 3.5:
            patient_factors.append(f"Low Red Cell Count (RBC: {raw_dict['RBC']:g} 10^12/L)")

        # If no specific abnormal findings were triggered among provided keys
        if not patient_factors:
            if provided_keys:
                # List provided features that matched reference ranges
                patient_factors = [f"{CBC_LABELS[k]} within normal reference ranges" for k in list(provided_keys)[:3]]
            else:
                patient_factors = ["No CBC parameters recorded in EHR"]
                
        return {
            "prediction": prediction_label,
            "riskScore": round(prob, 4),
            "modelVersion": self.cbc_metadata.get("model_version", "leukemia-cbc-v1"),
            "contributingFactors": patient_factors[:5],
            "analyzedAt": datetime.now(timezone.utc).isoformat(),
            "disclaimer": "AI risk assessment is for clinical decision support and is not a definitive medical diagnosis."
        }
