# Document AI Automated Training Pipeline

System for automated document processing, classification, and continuous model training using Google Document AI.

## System Architecture

Event-driven architecture:

```

   GCS Bucket     ────>   Cloud Function   ────>   Cloud Workflow 
  (Documents)             (Event Handler)          (Training Mgmt)

                                 │                        │
                                 v                        v
                            Firestore               Document AI  
                            (Metadata)               (Training)   

```

The system handles documents from upload through training without manual intervention. GCS uploads trigger processing that automatically classifies documents based on folder structure. When enough documents accumulate, the system kicks off model training and deploys improved versions. Built-in monitoring tracks everything from individual document processing to long-running training operations.

## Component Overview

### Processing Pipeline (`main.py`)
The main Cloud Function that gets triggered whenever a PDF lands in GCS. It figures out what type of document it is by looking at the folder name, runs it through OCR to extract text, and stores everything in Firestore. The function also keeps track of how many documents we have and decides when to kick off training (defaults to 3 for initial training, 2 for incremental). Built with retry logic since cloud services can be flaky.

### Auto-labeling System (`auto_labeling.py`)
This script processes batches of documents when you need to prepare training data manually. It handles 15 different document types, runs OCR on everything, and creates the proper JSON format that Document AI expects for training. Useful for initial setup or when you have a bunch of existing documents to process at once.

### Training Orchestration (`monitor-and-train.yaml`)
The Cloud Workflow that handles the actual training process. It waits for document imports to finish (which can take a while), then starts training once everything is ready. Has to monitor long-running operations since Document AI training can take 15-30 minutes. Also handles failures gracefully since training doesn't always work on the first try.

### Infrastructure Deployment (`deploy.sh`)
Deployment script that sets up everything needed in GCP. Creates the Cloud Function, Workflow, Firestore database, and all the IAM permissions. Also enables the necessary APIs and sets up a scheduled job for health checks. Does some validation at the end to make sure everything actually deployed correctly.

## Quick Start

### Setup

#### Environment Configuration
```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with actual values
# Required:
#   GCP_PROJECT_ID=project-id
#   DOCUMENT_AI_PROCESSOR_ID=processor-id
#   GCS_BUCKET_NAME=bucket-name
#   OCR_PROCESSOR_ID=ocr-processor-id

# Install dependencies
pip install -r requirements.txt
```

#### Alternative: Export Variables
```bash
export GCP_PROJECT_ID="project-id"
export DOCUMENT_AI_PROCESSOR_ID="processor-id"
export GCS_BUCKET_NAME="bucket-name"
export OCR_PROCESSOR_ID="ocr-processor-id"
```

#### Google Cloud Authentication
```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project $GCP_PROJECT_ID
```

### Deployment
```bash
chmod +x deploy.sh
./deploy.sh
```

Deployed components:
- Cloud Function for document processing
- Cloud Workflows for training orchestration
- Firestore for metadata management
- Cloud Scheduler for health monitoring
- Pub/Sub topics for messaging
- IAM roles and API enablement

### Document Processing
```bash
# Upload documents to trigger automated processing
gsutil -m cp -r /path/to/documents/* gs://your-bucket/documents/
# gsutil -m cp -r /Users/test/Downloads/classification-training-v1-Mar-2025/* gs://document-ai-test-veronica/documents/

# Or process existing documents with auto-labeling script
python3 auto_labeling.py
```

Automated workflow:
1. **Document Upload** → GCS event triggers Cloud Function
2. **Auto-classification** → Folder-based labeling with OCR processing
3. **Metadata Storage** → Document tracking in Firestore
4. **Threshold Check** → Training triggered when limits reached
5. **Model Training** → Automated training with 80/20 data split
6. **Model Deployment** → Automatic version management

### Monitoring

```bash
# Function logs
gcloud functions logs read document-ai-service --region=us-central1 --follow

# Workflow executions
gcloud workflows executions list workflow-1-veronica --location=us-central1

# Training operations
gcloud ai operations list --filter="type:TRAIN_PROCESSOR_VERSION"
```

## Configuration

### Training Parameters
Configurable thresholds stored in Firestore:
```json
{
  "min_documents_for_initial_training": 3,
  "min_documents_for_incremental": 2,
  "min_accuracy_for_deployment": 0.0,
  "check_interval_minutes": 60,
  "auto_deploy": true,
  "enabled": true
}
```

### Processing Logic
```python
# Threshold-based training triggers
if pending_documents >= threshold_initial:
    trigger_workflow('initial')
elif new_documents >= threshold_incremental:
    trigger_workflow('incremental')
```

### Document Format
Training documents use Document AI-compatible JSON:
```json
{
  "mimeType": "application/pdf",
  "text": "Extracted document text...",
  "uri": "gs://bucket/documents/type/doc.pdf",
  "entities": [{
    "type": "document_type",
    "confidence": 1.0,
    "textAnchor": {
      "textSegments": [{"startIndex": 0, "endIndex": 12}]
    }
  }]
}
```

## File Structure

```
document_ai_v2/
├── README.md                          # System documentation
├── requirements.txt                   # Python dependencies
├── .env.example                       # Environment variables template
├── .gitignore                         # Git ignore rules
├── deploy.sh                          # Infrastructure deployment script
├── main.py                            # Cloud Function for document processing
├── auto_labeling.py                   # Batch auto-labeling system
└── monitor-and-train.yaml             # Cloud Workflow for training orchestration
```

## Data Schema

### Firestore Collections

**processed_documents** - Document processing tracking:
```javascript
{
  document_id: "safe_name_hash123",
  gcs_uri: "gs://bucket/documents/TYPE/file.pdf",
  document_label: "TYPE",
  status: "pending_initial_training" | "completed",
  used_for_training: false,
  processor_id: "processor-id",
  created_at: timestamp,
  confidence_score: 0.95
}
```

**training_batches** - Training operation monitoring:
```javascript
{
  processor_id: "processor-id",
  training_operation: "projects/.../operations/123",
  status: "training" | "completed" | "failed",
  document_count: 25,
  started_at: timestamp,
  completed_at: timestamp
}
```

**training_configs** - System configuration:
```javascript
{
  processor_id: "processor-id",
  enabled: true,
  min_documents_for_initial_training: 3,
  min_documents_for_incremental: 2,
  check_interval_minutes: 60,
  document_types: ["TYPE1", "TYPE2", ...]
}
```

### Diagnostic Commands

```bash
# Function status and logs
gcloud functions describe document-ai-service --region=us-central1
gcloud functions logs read document-ai-service --region=us-central1 --limit=20

# Workflow monitoring
gcloud workflows describe workflow-1-veronica --location=us-central1
gcloud workflows executions list workflow-1-veronica --location=us-central1

# Training operations
gcloud ai operations list --filter="type:TRAIN_PROCESSOR_VERSION"

# Storage verification
gsutil ls gs://your-bucket/documents/
gsutil ls gs://your-bucket/final_labeled_documents/
```
