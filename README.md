# Automated Document AI Training System

A fully automated system for Google Document AI processors that automatically processes documents uploaded to Google Cloud Storage, manages training data, triggers training when thresholds are met, and deploys new models without manual intervention.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   GCS Bucket    │────▶│  Cloud Function  │────▶│  Cloud Workflow │
│  (Documents)    │     │  (Trigger)       │     │  (Training)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │                          │
                               ▼                          ▼
                        ┌─────────────┐           ┌──────────────┐
                        │  Firestore  │           │ Document AI  │
                        │  (State)    │           │ (Training)   │
                        └─────────────┘           └──────────────┘
```

## Key features

- GCS-triggered document processing and training
- Automatic initial and incremental training based on document thresholds
- Automatic model deployment and version management
- Live dashboard for system monitoring and health checks

1. **Initial Training**:
   - Collects documents until threshold is met
   - Triggers first model training
   - Deploys initial model

2. **Incremental Training**:
   - Processes new documents with current model
   - Triggers retraining when threshold reached
   - Deploys new version if accuracy improves

## Usage

1. Deploy system:
```bash
chmod +x deploy.sh
./deploy.sh
```

3. Upload PDFs to the GCS bucket:
```bash
gsutil -m cp -r /Users/test/Downloads/test_documents_v2/* gs://document-ai-test-veronica/documents/
```

4. Process auto-labeling:
```bash
python3 process-auto-labeling.py
```

5. (Optional) Configuration in Firestore
- `min_documents_for_initial_training`: 10 (default)
- `min_documents_for_incremental`: 5 (default)
- `min_accuracy_for_deployment`: 0.8 (default)
- `check_interval_minutes`: 360 (default)

# Document AI Complete Automation System

**Complete end-to-end automation: Creation → Deployment → Local Doc → GCS → Cloud Function → Firestore → Workflow → Document AI Processor → Update Firestore → Scheduler**

This system provides **zero-manual-intervention** Document AI automation with complete infrastructure deployment and continuous operation monitoring.

## 🎯 Complete System Architecture

```
Local Documents → GCS Upload → Cloud Function Trigger → Firestore Tracking → 
Cloud Workflow Orchestration → Document AI Processing → Training → 
Firestore Updates → Scheduler Monitoring → Continuous Retraining
```

## 🚀 Complete Infrastructure Components

### **1. Cloud Infrastructure**
- **Cloud Functions** (`cloud_function_main.py`) - GCS upload triggers with intelligent document processing
- **Cloud Workflows** (`automation_workflow.yaml`) - Complete training orchestration with import and training
- **Firestore** (`firestore.indexes.json`) - Document tracking and state management
- **Cloud Scheduler** - Periodic training checks every 6 hours
- **Pub/Sub** - Event-driven communication between components

### **2. Document Processing Pipeline**
- **OCR Processing** (`2369784b09e9d56a`) - Text extraction from PDFs
- **Intelligent Auto-labeling** - Exact folder-name-based labeling with proper Document AI JSON format
- **Classification Training** (`ddc065df69bfa3b5`) - Custom model training with auto-split
- **Continuous Learning** - Automatic retraining with new documents

### **3. Monitoring & Management**
- **Real-time Status** - Firestore document tracking
- **Operation Monitoring** - Training and import progress tracking
- **Health Checks** - Automated system validation
- **Error Handling** - Automatic retry and failure notifications

## 🎬 Quick Start - Complete Deployment

### **Phase 1: Infrastructure Setup**

1. **Prerequisites**
```bash
# Authenticate
gcloud auth login
gcloud auth application-default login
gcloud config set project tetrix-462721
gcloud auth application-default set-quota-project tetrix-462721

# Install dependencies
pip install -r requirements.txt
```

2. **Deploy Complete Infrastructure**
```bash
# Deploy all components: Cloud Functions, Workflows, Firestore, Scheduler
chmod +x deploy.sh
./deploy.sh
```

**What gets deployed:**
- ✅ Cloud Function for GCS triggers with intelligent document processing
- ✅ Cloud Workflows for complete training orchestration  
- ✅ Firestore with proper indexes and document tracking
- ✅ Cloud Scheduler for periodic health checks
- ✅ Pub/Sub topics for messaging
- ✅ IAM roles and permissions
- ✅ API enablement

### **Phase 2: Document Processing**

3. **Organize Documents by Label**
```
/Users/test/Downloads/test_documents_v2/
├── capital_call/
│   ├── document1.pdf
│   └── document2.pdf
├── financial_statement/
│   ├── statement1.pdf
│   └── statement2.pdf
└── distribution_notice/
    ├── notice1.pdf
    └── notice2.pdf
```

4. **Upload and Watch Complete Automation**
```bash
# Upload documents - complete automation takes over
gsutil -m cp -r /Users/test/Downloads/test_documents_v2/* gs://document-ai-test-veronica/documents/
```

**Automatic Flow After Upload:**
1. 🔄 Cloud Function triggered on GCS upload
2. 📝 Document auto-labeled based on exact folder name (`capital_call` → `capital_call` label)
3. 🤖 OCR processing extracts text and document structure
4. 📄 Proper Document AI JSON format created with entities and labels
5. 💾 Metadata stored in Firestore with training status
6. 🎯 Training threshold checked (3 initial / 2 incremental)
7. ⚡ Cloud Workflow triggered when threshold met
8. 📊 Documents imported with auto-split (80% training / 20% test)
9. 🎓 Training started automatically
10. 📈 Firestore updated with operation results

### **Phase 3: Continuous Operation**

5. **Add New Documents (Triggers Retraining)**
```bash
# Any new uploads automatically trigger retraining
gsutil cp new_document.pdf gs://document-ai-test-veronica/documents/capital_call/
```

6. **Monitor Operations**
```bash
# Check Cloud Function logs
gcloud functions logs read document-ai-service --region=us-central1 --limit=10

# Check workflow executions
gcloud workflows executions list automation-workflow --location=us-central1 --limit=5

# Monitor specific operation
gcloud workflows executions describe EXECUTION_ID --workflow automation-workflow --location us-central1
```

## 📊 Complete System Flow

### **1. Document Upload Trigger**
```
PDF Upload → GCS Event → Cloud Function → Folder-based Labeling → OCR Processing → JSON Creation → Firestore Storage
```

### **2. Intelligent Document Processing**
```python
# Cloud Function processing logic
1. Extract folder name from GCS path (documents/capital_call/doc.pdf)
2. Auto-label with exact folder name: "capital_call" 
3. Process with OCR to extract text and structure
4. Create Document AI JSON format with proper entities
5. Store metadata in Firestore with training status
```

### **3. Training Threshold Logic**
```python
# Automatic threshold checking (in Cloud Function)
if pending_documents >= 3:  # Initial training
    trigger_workflow('initial')
elif new_documents >= 2:   # Incremental training
    trigger_workflow('incremental')
```

### **4. Cloud Workflow Orchestration**
```yaml
# automation_workflow.yaml - Complete training workflow
- organize_documents:
    # Create properly labeled JSON documents from Firestore metadata
    
- import_documents:
    call: http.post documentai.v1beta3.importDocuments
    args:
      autoSplitConfig:
        trainingSplitRatio: 0.8

- start_training:
    call: http.post documentai.v1.train
    
- update_firestore:
    call: http.patch firestore.v1.patch
    # Updates training status in real-time
```

### **5. Continuous Monitoring**
```
Cloud Scheduler (6h) → Check Firestore → Trigger Training → Monitor Operations → Update Status
```

## 🏗️ Complete File Structure

```
document_ai/
├── README.md                          # Complete documentation
├── requirements.txt                   # Python dependencies
│
├── 🚀 COMPLETE AUTOMATION SYSTEM
├── deploy.sh                          # Complete infrastructure deployment
├── cloud_function_main.py             # GCS-triggered Cloud Function with intelligent processing
├── automation_workflow.yaml           # Complete training orchestration workflow
├── firestore.indexes.json             # Firestore configuration and indexes
├── update_training_status.py          # Utility to manage training state
├── clear_dataset.py                   # Utility to clear processor dataset
├── create_fresh_processor.py          # Utility to create new clean processor
│
├── 📦 UTILITY SCRIPTS
├── document_ai/                       # Core utilities package
│   ├── __init__.py
│   ├── utils.py                       # Common functions
│   ├── api.py                         # Document AI API wrapper
│   ├── client.py                      # Enhanced client utilities
│   ├── incremental_training.py        # AutomatedTrainingManager
│   └── models.py                      # Data models and types
│
└── ⚡ MANUAL MODE SCRIPTS (Optional)
    ├── document_pipeline.py           # Manual pipeline execution
    ├── import_and_train.py            # Direct import/training
    ├── auto_labeling.py               # Manual document labeling
    └── manual_pipeline.py             # Alternative manual approach
```

## 📋 Configuration

### **Pre-configured Settings**
- **Project ID**: `tetrix-462721`
- **OCR Processor**: `2369784b09e9d56a` (text extraction)
- **Classifier Processor**: `ddc065df69bfa3b5` (training target)
- **GCS Bucket**: `document-ai-test-veronica`
- **Location**: `us`

### **Firestore Collections Schema**
```javascript
// processed_documents - Track all document processing
{
  document_id: "doc_12345",
  gcs_uri: "gs://bucket/documents/capital_call/doc1.pdf",
  document_label: "capital_call",  // Exact folder name
  status: "pending_initial_training" | "completed",
  used_for_training: false,
  processor_id: "ddc065df69bfa3b5",
  created_at: timestamp,
  document_type: "CAPITAL_CALL",  // OCR prediction
  confidence: 0.95
}

// training_batches - Monitor training operations
{
  processor_id: "ddc065df69bfa3b5",
  training_operation: "projects/.../operations/12345",
  status: "training" | "completed" | "failed",
  document_count: 25,
  training_gcs_prefix: "gs://bucket/final_labeled_documents/",
  started_at: timestamp,
  completed_at: timestamp
}

// training_configs - Automation settings
{
  processor_id: "ddc065df69bfa3b5",
  enabled: true,
  min_documents_for_initial_training: 3,
  min_documents_for_incremental: 2,
  check_interval_minutes: 360,
  document_types: ["capital_call", "financial_statement", "distribution_notice"]
}
```

### **Document AI JSON Format**
```json
{
  "mimeType": "application/pdf",
  "text": "Extracted document text...",
  "uri": "gs://bucket/documents/capital_call/doc1.pdf",
  "entities": [
    {
      "type": "capital_call",
      "mentionText": "capital_call", 
      "confidence": 1.0,
      "textAnchor": {
        "textSegments": [{"startIndex": 0, "endIndex": 12}]
      }
    }
  ],
  "pages": [{"pageNumber": 1, "dimension": {...}}]
}
```

## 🔍 Monitoring & Verification

### **Real-time Monitoring Commands**
```bash
# Cloud Function logs (document processing)
gcloud functions logs read document-ai-service --region=us-central1 --limit=20

# Workflow executions (training operations) 
gcloud workflows executions list automation-workflow --location=us-central1 --limit=10

# Check specific workflow execution
gcloud workflows executions describe EXECUTION_ID --workflow automation-workflow --location us-central1

# Firestore document tracking
gcloud firestore databases list --project=tetrix-462721
```

### **Console Links for Monitoring**
- **Document AI Processor**: https://console.cloud.google.com/ai/document-ai/processors/details/ddc065df69bfa3b5?project=tetrix-462721
- **Cloud Functions**: https://console.cloud.google.com/functions/list?project=tetrix-462721  
- **Cloud Workflows**: https://console.cloud.google.com/workflows?project=tetrix-462721
- **Firestore Database**: https://console.cloud.google.com/firestore?project=tetrix-462721
- **Cloud Scheduler**: https://console.cloud.google.com/cloudscheduler?project=tetrix-462721
- **Cloud Storage**: https://console.cloud.google.com/storage/browser/document-ai-test-veronica?project=tetrix-462721

## 🎯 Success Verification

After deployment and document upload, verify complete automation:

### **1. Cloud Function Processing**
```bash
# Check function logs for document processing and labeling
gcloud functions logs read document-ai-service --region=us-central1 --limit=10

# Expected log entries:
# "Auto-labeled document as capital_call based on subfolder"
# "Document saved with label: capital_call" 
# "Training threshold met: 5 >= 3"
# "Started workflow execution: projects/.../executions/..."
```

### **2. Workflow Execution**
```bash
# Check workflow status and results
gcloud workflows executions list automation-workflow --location=us-central1 --limit=5

# Check specific execution details
gcloud workflows executions describe EXECUTION_ID --workflow automation-workflow --location us-central1
```

### **3. Document AI Operations**
```bash
# Check for active training operations
# Note: Use Document AI console for operation monitoring
# https://console.cloud.google.com/ai/document-ai/processors/details/ddc065df69bfa3b5?project=tetrix-462721
```

### **4. Labeled Documents Created**
```bash
# Verify labeled JSON documents were created
gsutil ls gs://document-ai-test-veronica/final_labeled_documents/

# Check document structure
gsutil cat gs://document-ai-test-veronica/final_labeled_documents/capital_call/doc.json | jq '.entities[0].type'
# Should return: "capital_call"
```

## 🔄 Continuous Operation Features

### **Automatic Retraining**
- **Upload trigger**: Any new PDF upload automatically triggers processing and potential retraining
- **Intelligent thresholds**: Initial training requires 3+ documents, incremental requires 2+ new documents
- **Scheduled health checks**: Every 6 hours via Cloud Scheduler
- **Error handling**: Automatic retries and comprehensive failure notifications
- **State management**: Persistent tracking in Firestore prevents duplicate processing

### **Labeling Accuracy**
- **Exact folder matching**: `capital_call` folder → `capital_call` label (no case conversion)
- **Document AI JSON format**: Proper entities structure with textAnchor for training
- **OCR integration**: Full text extraction while preserving folder-based labels
- **Schema consistency**: Labels match processor training schema exactly

## 🔧 Technical Implementation Details

### **Event-Driven Architecture**
- **GCS Events** → Cloud Function → Intelligent Processing → Firestore → Workflow Orchestration
- **Pub/Sub Messaging** for reliable component communication
- **Automatic scaling** based on document volume and processing load

### **Document Processing Pipeline**
1. **GCS Upload Detection**: Cloud Function triggered on object creation
2. **Folder-based Labeling**: Extract exact folder name as document label
3. **OCR Processing**: Extract text and document structure using OCR processor
4. **JSON Creation**: Build proper Document AI training format with entities
5. **Firestore Storage**: Persist metadata and training status
6. **Threshold Evaluation**: Check if training should be triggered
7. **Workflow Orchestration**: Execute complete training pipeline

### **State Management & Reliability**
- **Firestore persistence**: All document states and training operations tracked
- **Operation monitoring**: Long-running training operations monitored for completion
- **Error recovery**: Automatic retries with exponential backoff
- **Duplicate prevention**: Document IDs and processing status prevent reprocessing

### **Security & Permissions**
- **Service accounts**: Minimal required permissions for each component
- **IAM roles**: Properly configured for Cloud Functions, Workflows, and Document AI
- **Secure API access**: OAuth2 authentication for all Google Cloud API calls

## 🚨 Troubleshooting Guide

### **Cloud Function Issues**
```bash
# Check function deployment status
gcloud functions describe document-ai-service --region=us-central1

# View detailed processing logs
gcloud functions logs read document-ai-service --region=us-central1 --limit=50

# Common issues:
# - "Skipping non-document file" → Only PDF files are processed
# - "Auto-labeled document as X" → Confirm correct folder-based labeling
# - "Training threshold met" → Confirms threshold logic working
```

### **Workflow Issues**  
```bash
# Check workflow deployment status
gcloud workflows describe automation-workflow --location=us-central1

# View execution history and failures
gcloud workflows executions list automation-workflow --location=us-central1 --limit=10

# Check specific execution details
gcloud workflows executions describe EXECUTION_ID --workflow automation-workflow --location us-central1

# Common issues:
# - Import operation failures → Check GCS permissions and document format
# - Training operation failures → Check processor state and dataset
```

### **Document AI Dataset Issues**
```bash
# Clear dataset if needed (manual console operation)
# Go to: https://console.cloud.google.com/ai/document-ai/processors/details/ddc065df69bfa3b5?project=tetrix-462721
# Look for "Dataset" → "Clear" or "Reset" options

# Create fresh processor if needed
python3 create_fresh_processor.py

# Clear training status in Firestore
python3 update_training_status.py
```

This system provides **complete automation** from document upload to trained model deployment with **zero manual intervention** required for ongoing operation. The intelligent processing ensures accurate folder-based labeling while maintaining proper Document AI training format compatibility.