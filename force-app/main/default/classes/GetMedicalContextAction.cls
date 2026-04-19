/**
 * GetMedicalContextAction
 * Agentforce action that returns curated oncology/pharma medical context:
 * drug names, Indian physician name patterns, Hinglish visit phrases,
 * and facility names. Used to ground the AI agent with domain knowledge.
 */
public with sharing class GetMedicalContextAction {

    @InvocableMethod(
        label       = 'Get Medical Context'
        description = 'Returns oncology drug information, Indian physician name patterns, Hinglish phrases, and healthcare facility names to ground agent responses.'
        category    = 'OncoGlobal Visit Management'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(buildContext(req));
        }
        return results;
    }

    private static Result buildContext(Request req) {
        Result res = new Result();
        res.success = true;

        String category = String.isBlank(req.category) ? 'ALL' : req.category.toUpperCase();

        if (category == 'ALL' || category == 'DRUGS') {
            res.drugReference = buildDrugReference();
        }
        if (category == 'ALL' || category == 'NAMES') {
            res.namePatterns = buildNamePatterns();
        }
        if (category == 'ALL' || category == 'PHRASES') {
            res.hinglishPhrases = buildHinglishPhrases();
        }
        if (category == 'ALL' || category == 'FACILITIES') {
            res.facilityReference = buildFacilityReference();
        }
        if (category == 'ALL' || category == 'TERMS') {
            res.medicalTerms = buildMedicalTerms();
        }

        res.fullContext = String.join(
            new List<String>{
                res.drugReference,
                res.namePatterns,
                res.hinglishPhrases,
                res.facilityReference,
                res.medicalTerms
            },
            '\n\n'
        );

        return res;
    }

    // ─── Drug Reference ────────────────────────────────────────────────────────

    private static String buildDrugReference() {
        return 'ONCOLOGY DRUGS IN INDIA:\n'
            + 'Immunotherapy (Checkpoint Inhibitors):\n'
            + '  Keytruda (pembrolizumab) — anti-PD-1, MSD/Merck. Uses: NSCLC, melanoma, HNSCC, gastric, bladder, cervical, MSI-H. Admin: IV 200mg Q3W or 400mg Q6W.\n'
            + '  Opdivo (nivolumab) — anti-PD-1, BMS. Uses: NSCLC, RCC, HNSCC, HCC, colorectal MSI-H, melanoma. Admin: IV 240mg Q2W or 480mg Q4W.\n'
            + '  Tecentriq (atezolizumab) — anti-PD-L1, Roche. Uses: NSCLC, SCLC, bladder, TNBC.\n'
            + '  Imfinzi (durvalumab) — anti-PD-L1, AstraZeneca. Uses: Stage III NSCLC, SCLC.\n'
            + 'Targeted Therapy — EGFR/ALK/ROS1:\n'
            + '  Tagrisso (osimertinib) — 3rd gen EGFR TKI, AstraZeneca. EGFR exon19del/L858R + T790M.\n'
            + '  Iressa (gefitinib) — 1st gen EGFR TKI, AstraZeneca. NSCLC EGFR+.\n'
            + '  Tarceva (erlotinib) — 1st gen EGFR TKI, Roche. NSCLC, pancreatic.\n'
            + '  Gilotrif (afatinib) — 2nd gen EGFR TKI, Boehringer. NSCLC EGFR+.\n'
            + '  Xalkori (crizotinib) — ALK/ROS1/MET inhibitor, Pfizer.\n'
            + '  Alecensa (alectinib) — 2nd gen ALK inhibitor, Roche.\n'
            + 'Targeted — HER2/VEGF/CDK4-6:\n'
            + '  Herceptin (trastuzumab) — HER2, Roche. HER2+ breast, gastric.\n'
            + '  Avastin (bevacizumab) — anti-VEGF, Roche. CRC, NSCLC, GBM, ovarian.\n'
            + '  Ibrance (palbociclib) — CDK4/6, Pfizer. HR+ HER2- breast.\n'
            + '  Kisqali (ribociclib) — CDK4/6, Novartis. HR+ HER2- breast.\n'
            + 'Hematology:\n'
            + '  Gleevec/Glivec (imatinib) — BCR-ABL, Novartis. CML, GIST.\n'
            + '  Revlimid (lenalidomide) — IMiD, BMS. Multiple myeloma, MDS.\n'
            + '  Velcade (bortezomib) — proteasome inhibitor, Janssen. Multiple myeloma.\n'
            + '  Calquence (acalabrutinib) — BTK inhibitor, AstraZeneca. CLL, MCL.\n'
            + 'Prostate/Ovarian:\n'
            + '  Zytiga (abiraterone) — CYP17A1 inhibitor, Janssen. mCRPC.\n'
            + '  Xtandi (enzalutamide) — AR inhibitor, Astellas/Pfizer. mCRPC.\n'
            + '  Lynparza (olaparib) — PARP inhibitor, AstraZeneca. BRCA+ ovarian, breast, pancreatic.\n'
            + 'Indian Generic/Biosimilar brands: Biomab EGFR (nimotuzumab), Temoside (temozolomide), Xbira (abiraterone generic), Trastumab (trastuzumab biosimilar).';
    }

    // ─── Indian Name Patterns ───────────────────────────────────────────────────

    private static String buildNamePatterns() {
        return 'INDIAN PHYSICIAN NAME PATTERNS:\n'
            + 'Common First Names (Male): Rajesh, Suresh, Mahesh, Ramesh, Dinesh, Naresh, Umesh, Rakesh, Mukesh, Ganesh, Vijay, Sanjay, Ajay, Ravi, Arun, Anil, Vishal, Vivek, Amit, Nitin, Rahul, Rohit, Vikram, Piyush, Ashok, Santosh, Pradeep, Deepak, Abhijit, Girish\n'
            + 'Common First Names (Female): Priya, Anita, Sunita, Kavita, Savita, Meena, Seema, Reena, Nisha, Usha, Rekha, Geeta, Lata, Suman, Smita, Pooja, Deepa, Swati, Ananya, Divya, Shruti, Neha, Sneha, Pallavi, Madhuri\n'
            + 'Common Last Names by Region:\n'
            + '  North India: Sharma, Gupta, Verma, Singh, Agarwal, Srivastava, Mishra, Yadav, Tiwari, Joshi, Pandey, Shukla, Dubey\n'
            + '  West India (Maharashtra/Gujarat): Patel, Shah, Mehta, Desai, Jain, Patil, Kulkarni, Deshpande, Joshi, Thakkar, Modi\n'
            + '  South India (Tamil): Iyer, Iyengar, Krishnan, Subramanian, Rajan, Venkatesh, Narayanan, Sundaram, Ramaswamy, Anand\n'
            + '  South India (Kerala): Nair, Menon, Pillai, Varma, Kurup, Karunakaran, Krishnakumar, Madhavan\n'
            + '  South India (Karnataka): Rao, Reddy, Hegde, Shetty, Gowda, Kamath, Bhat\n'
            + '  East India (Bengal): Bose, Chatterjee, Mukherjee, Banerjee, Ghosh, Sen, Roy, Das, Dey\n'
            + 'Honorifics: Always "Dr." before name. Reps may say "Sharma sir", "Sharma ji", "Sharma madam" — all refer to Dr. Sharma.\n'
            + 'Specialties: Oncologist, Medical Oncologist, Surgical Oncologist, Radiation Oncologist, Hemato-Oncologist, Hematologist, Breast Oncologist, Gynecologic Oncologist.';
    }

    // ─── Hinglish Visit Phrases ─────────────────────────────────────────────────

    private static String buildHinglishPhrases() {
        return 'HINGLISH MEDICAL REP PHRASES (Hindi-English mix):\n'
            + 'Visit Logging:\n'
            + '  "Visit log karna hai" → Log this visit\n'
            + '  "Aaj Dr. Sharma ke paas gaya tha" → I visited Dr. Sharma today\n'
            + '  "Visit complete ho gaya" → Visit is done\n'
            + '  "Report banana hai" → Need to create a report\n'
            + 'Visit Outcomes:\n'
            + '  "Bahut accha gaya / Positive tha" → Very positive visit\n'
            + '  "Theek-thak raha / Neutral tha" → Neutral visit\n'
            + '  "Acha nahi gaya / Negative tha" → Negative visit\n'
            + '  "Follow up chahiye / dobara jaana hai" → Need to follow up\n'
            + '  "Interested lag rahe the" → They seemed interested\n'
            + '  "Abhi sochenge" → They will think about it\n'
            + 'Discussion Topics:\n'
            + '  "Keytruda ke baare mein baat ki" → Discussed Keytruda\n'
            + '  "Trial enrollment ke baare mein discuss kiya" → Discussed trial enrollment\n'
            + '  "Formulary mein daalne ki request ki" → Requested formulary addition\n'
            + '  "Samples diye/diye the" → Gave samples\n'
            + '  "Data share kiya" → Shared clinical data\n'
            + '  "CME sponsor kiya / karenge" → Sponsored/will sponsor CME\n'
            + '  "TAT ki problem thi" → There was a turnaround time issue\n'
            + '  "EGFR mutation wale patient ke liye" → For EGFR mutation patients\n'
            + 'Follow-Up Actions:\n'
            + '  "Literature bhejni hai" → Need to send literature\n'
            + '  "Call karna hai unhe" → Need to call them\n'
            + '  "Sample arrange karna hai" → Need to arrange samples\n'
            + '  "Meeting set up karni hai" → Need to set up a meeting\n'
            + '  "Unka reference chahiye" → Need their reference\n'
            + 'Expenses:\n'
            + '  "Lunch ke liye 500 rupees gaye" → Spent Rs. 500 on lunch\n'
            + '  "Train ka ticket 1200 tha" → Train ticket was Rs. 1200\n'
            + '  "Hotel mein ruka, 2500 tha" → Stayed at hotel, cost Rs. 2500\n'
            + '  "Samples ki cost nahi hoti" → Samples cost not counted\n'
            + '  "Auto/cab ka 200 tha" → Auto/cab was Rs. 200\n'
            + 'Meeting Locations:\n'
            + '  "OPD mein mila" → Met in outpatient department\n'
            + '  "Chamber mein gaya" → Went to their clinic/chamber\n'
            + '  "Hospital ke bahar mila" → Met outside the hospital\n'
            + '  "Conference mein mila" → Met at a conference\n'
            + '  "Lunch mein mila" → Met over lunch';
    }

    // ─── Healthcare Facilities ──────────────────────────────────────────────────

    private static String buildFacilityReference() {
        return 'INDIAN HEALTHCARE FACILITIES:\n'
            + 'Premier Cancer Centers:\n'
            + '  Tata Memorial Hospital (TMH) — Mumbai, premier cancer research & treatment\n'
            + '  Rajiv Gandhi Cancer Institute (RGCI) — New Delhi\n'
            + '  Cancer Institute (Adyar) — Chennai\n'
            + '  Kidwai Memorial Institute of Oncology — Bangalore\n'
            + '  MNJ Institute of Oncology — Hyderabad\n'
            + '  HCG (Healthcare Global Oncology) — Pan-India oncology chain\n'
            + '  Shaukat Khanum — Pakistan (for border territories)\n'
            + 'Corporate Hospital Chains:\n'
            + '  Apollo Hospitals — Apollo Cancer Centre across all metros\n'
            + '  Fortis Healthcare — Fortis Memorial Research Institute Gurgaon\n'
            + '  Max Healthcare — Max Cancer Centre Delhi/NCR\n'
            + '  Manipal Hospitals — Manipal Comprehensive Cancer Centre\n'
            + '  Narayana Health — Narayana Cancer Centre\n'
            + '  Medanta — Medanta Cancer Institute, Gurgaon\n'
            + '  Aster Hospitals — South India\n'
            + '  Columbia Asia — Metro cities\n'
            + '  Care Hospitals — Central/South India\n'
            + 'Government Hospitals:\n'
            + '  AIIMS (All India Institute of Medical Sciences) — Delhi, Bhopal, Bhubaneswar, Jodhpur, Patna, Raipur, Rishikesh\n'
            + '  PGIMER — Chandigarh\n'
            + '  NIMHANS — Bangalore (neuro)\n'
            + '  KEM Hospital — Mumbai\n'
            + '  Safdarjung Hospital — Delhi\n'
            + 'Territories & Cities: Mumbai South, Mumbai North, Mumbai Suburbs, Delhi, Delhi NCR, Bangalore East, Bangalore West, Bangalore North, Chennai, Hyderabad, Pune, Ahmedabad, Kolkata, Jaipur, Lucknow, Chandigarh, Surat, Nagpur, Indore, Bhopal, Kochi, Coimbatore, Vizag.';
    }

    // ─── Medical Terms ──────────────────────────────────────────────────────────

    private static String buildMedicalTerms() {
        return 'PHARMA/ONCOLOGY ABBREVIATIONS:\n'
            + 'Cancer Types: NSCLC (Non-Small Cell Lung Cancer), SCLC (Small Cell Lung Cancer), CRC (Colorectal Cancer), HCC (Hepatocellular Carcinoma), RCC (Renal Cell Carcinoma), TNBC (Triple Negative Breast Cancer), GBM (Glioblastoma), CLL (Chronic Lymphocytic Leukemia), MCL (Mantle Cell Lymphoma), CML (Chronic Myeloid Leukemia), AML (Acute Myeloid Leukemia), MM (Multiple Myeloma), mCRPC (metastatic Castration-Resistant Prostate Cancer), GIST (Gastrointestinal Stromal Tumor), HNSCC (Head & Neck Squamous Cell Carcinoma)\n'
            + 'Biomarkers: PD-L1 (Programmed Death-Ligand 1), EGFR (Epidermal Growth Factor Receptor), ALK (Anaplastic Lymphoma Kinase), ROS1, KRAS, BRAF, HER2 (Human Epidermal Growth Factor Receptor 2), BRCA1/2, MSI-H (Microsatellite Instability-High), TMB (Tumor Mutational Burden), VEGF (Vascular Endothelial Growth Factor), BCR-ABL\n'
            + 'Clinical Outcomes: OS (Overall Survival), PFS (Progression-Free Survival), DFS (Disease-Free Survival), ORR (Objective Response Rate), DCR (Disease Control Rate), CR (Complete Response), PR (Partial Response), SD (Stable Disease), PD (Progressive Disease), DoR (Duration of Response)\n'
            + 'Performance: ECOG (Eastern Cooperative Oncology Group score 0-5), KPS (Karnofsky Performance Status 0-100%), PS (Performance Status)\n'
            + 'Clinical Trials: IND (Investigational New Drug), NDA (New Drug Application), Phase I/II/III/IV, IRB (Institutional Review Board), IEC (Independent Ethics Committee — Indian equivalent of IRB), CDSCO (Central Drugs Standard Control Organisation — Indian FDA), GCP (Good Clinical Practice), ICF (Informed Consent Form), AE (Adverse Event), SAE (Serious Adverse Event), SUSAR\n'
            + 'Pharma Business: MR (Medical Representative), HCP (Healthcare Provider), KOL (Key Opinion Leader), SOC (Standard of Care), TAT (Turnaround Time), OPD (Outpatient Department), IPD (Inpatient Department), CME (Continuing Medical Education), TL (Territory Leader), RSM (Regional Sales Manager), NSM (National Sales Manager), PO (Purchase Order)\n'
            + 'Treatment: IV (Intravenous), SC (Subcutaneous), PO (Per Oral), Q2W/Q3W/Q4W/Q6W (dosing frequency), TKI (Tyrosine Kinase Inhibitor), mAb (monoclonal antibody), IO (Immuno-Oncology), ADC (Antibody-Drug Conjugate), CART (CAR-T cell therapy), BSC (Best Supportive Care), CCRT (Concurrent Chemoradiotherapy)';
    }

    // ─── Inner Classes ──────────────────────────────────────────────────────────

    public class Request {
        @InvocableVariable(
            label       = 'Context Category'
            description = 'Category of context to retrieve: ALL, DRUGS, NAMES, PHRASES, FACILITIES, TERMS. Defaults to ALL.'
            required    = false
        )
        public String category;
    }

    public class Result {
        @InvocableVariable(label = 'Success')
        public Boolean success;

        @InvocableVariable(label = 'Full Context')
        public String fullContext;

        @InvocableVariable(label = 'Drug Reference')
        public String drugReference;

        @InvocableVariable(label = 'Name Patterns')
        public String namePatterns;

        @InvocableVariable(label = 'Hinglish Phrases')
        public String hinglishPhrases;

        @InvocableVariable(label = 'Facility Reference')
        public String facilityReference;

        @InvocableVariable(label = 'Medical Terms')
        public String medicalTerms;

        @InvocableVariable(label = 'Error Message')
        public String errorMessage;
    }
}
