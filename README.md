# Document AI Auto-Training Pipeline v2 ✅

## Architecture Overview

```
Document Upload → Cloud Function → OCR Processing → Auto-Labeling → 
Import to Doc AI → Workflow Monitor → Automatic Training
```

## Key Features

1. **Automatic Document Processing**
   - Detects new PDF uploads in `documents/` folder
   - Auto-labels based on subfolder structure
   - Batches documents when threshold is met

2. **Smart OCR Integration**
   - Uses OCR processor to extract text and structure
   - Creates properly formatted labeled documents
   - Preserves original document URIs

3. **Threshold-Based Training**
   - Initial training: 3 documents (configurable)
   - Incremental training: 2 documents (configurable)
   - Automatic detection of processor state

4. **Robust Workflow Management**
   - Monitors import operations to completion
   - Automatically triggers training after successful import
   - Handles failures gracefully with detailed logging

## Files Modified

### 1. `main.py` (Cloud Function)
- **Complete rewrite** to integrate OCR processing
- Batch processing when threshold is met
- Creates labeled JSON documents in Document AI format
- Imports documents and triggers workflow

### 2. `monitor-and-train.yaml` (Workflow)
- Monitors import operation with timeout protection
- Automatically starts training after import success
- Clean error handling and status reporting

### 3. `deploy.sh` (Deployment Script)
- Updated with OCR processor configuration
- Gen2 Cloud Function deployment
- Complete environment setup

### 4. `requirements.txt`
- Minimal dependencies for optimal performance
- Includes `requests` for Document AI beta API calls

## How It Works

1. **Upload Detection**
   ```bash
   # Single file
   gsutil cp invoice.pdf gs://bucket/documents/FINANCIAL_STATEMENT/
   
   # Batch upload
   gsutil -m cp -r capital_calls/* gs://bucket/documents/CAPITAL_CALL/
   ```

2. **Auto-Labeling**
   - Subfolder name becomes document label
   - Example: `documents/TAX/form.pdf` → Label: `TAX`

3. **Batch Processing**
   - Waits for threshold (3 for initial, 2 for incremental)
   - Processes all pending documents together
   - Creates labeled JSONs in `labeled_documents/`

4. **Import & Training**
   - Imports labeled documents to Document AI
   - Workflow monitors import progress
   - Automatically starts training when import completes

## Key Improvements

1. **Efficient Batching**: Only processes when threshold is met
2. **No Manual Steps**: Fully automated from upload to training
3. **Minimal File Creation**: Reuses existing storage, creates only necessary labeled JSONs
4. **Production-Ready**: Proper error handling, logging, and monitoring

## Deployment

```bash
# Set environment variables
export GCP_PROJECT_ID="your-project"
export DOCUMENT_AI_PROCESSOR_ID="your-classifier-id"
export OCR_PROCESSOR_ID="your-ocr-id"
export GCS_BUCKET_NAME="your-bucket"

# Deploy
./deploy.sh
```

## Monitoring

```bash
# Watch real-time logs
gcloud functions logs read document-ai-service --region=us-central1 --follow

# Check Firestore status
gcloud firestore databases execute-sql \
  --database="(default)" \
  --sql="SELECT * FROM processed_documents WHERE status = 'pending_labeling'"
```