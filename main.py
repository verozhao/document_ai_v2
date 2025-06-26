"""
Cloud Function that processes document uploads, auto-labels them,
and triggers training when thresholds are met.
"""

import os
import json
import hashlib
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional
import time

from google.cloud import documentai_v1 as documentai
from google.cloud import firestore
from google.cloud import storage
from google.api_core.client_options import ClientOptions
from google.cloud.workflows import executions_v1
from google.cloud.workflows.executions_v1 import Execution

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = os.environ.get('GCP_PROJECT_ID')
CLASSIFIER_PROCESSOR_ID = os.environ.get('DOCUMENT_AI_PROCESSOR_ID')
OCR_PROCESSOR_ID = os.environ.get('OCR_PROCESSOR_ID', '2369784b09e9d56a')  # Default OCR processor
LOCATION = os.environ.get('DOCUMENT_AI_LOCATION', 'us')
WORKFLOW_NAME = os.environ.get('WORKFLOW_NAME', 'monitor-and-train')
WORKFLOW_LOCATION = 'us-central1'
BUCKET_NAME = os.environ.get('GCS_BUCKET_NAME')

# Initialize clients
db = firestore.Client(project=PROJECT_ID)
storage_client = storage.Client(project=PROJECT_ID)
workflow_execution_client = executions_v1.ExecutionsClient()

# Document AI client
opts = ClientOptions(api_endpoint=f"{LOCATION}-documentai.googleapis.com")
docai_client = documentai.DocumentProcessorServiceClient(client_options=opts)

def process_document_upload(event, context):
    """Cloud Function triggered by GCS object creation."""
    try:
        # Extract event data for 1st gen function
        bucket_name = event['bucket']
        file_name = event['name']
        content_type = event.get('contentType', '')
        
        logger.info(f"Processing: gs://{bucket_name}/{file_name}")
        
        # Filter only PDFs in documents folder
        if not file_name.startswith('documents/') or not file_name.endswith('.pdf'):
            logger.info(f"Skipping non-document: {file_name}")
            return {'status': 'skipped'}

        # Generate document ID
        doc_id = generate_document_id(file_name)
        
        # Check if already processed
        doc_ref = db.collection('processed_documents').document(doc_id)
        if doc_ref.get().exists:
            logger.info(f"Already processed: {doc_id}")
            return {'status': 'already_processed'}
        
        # Extract document type from subfolder
        document_type = extract_document_type(file_name)
        
        # Record document
        doc_data = {
            'document_id': doc_id,
            'gcs_uri': f"gs://{bucket_name}/{file_name}",
            'file_name': file_name,
            'document_type': document_type,
            'processor_id': CLASSIFIER_PROCESSOR_ID,
            'status': 'pending_labeling',
            'created_at': datetime.now(timezone.utc),
            'used_for_training': False
        }
        doc_ref.set(doc_data)
        
        # Check if we should trigger batch processing
        should_process, batch_docs = check_processing_threshold()
        
        if should_process:
            logger.info(f"Threshold met with {len(batch_docs)} documents")
            
            # Process batch: OCR + label + import
            import_operation = process_document_batch(batch_docs)
            
            if import_operation:
                # Trigger workflow to monitor import and train
                trigger_training_workflow(import_operation)
                return {
                    'status': 'batch_triggered',
                    'batch_size': len(batch_docs),
                    'import_operation': import_operation
                }
        
        return {'status': 'queued', 'document_id': doc_id}
        
    except Exception as e:
        logger.error(f"Error: {str(e)}", exc_info=True)
        return {'status': 'error', 'error': str(e)}


def generate_document_id(file_name: str) -> str:
    """Generate unique document ID."""
    base_name = os.path.basename(file_name).rsplit('.', 1)[0]
    safe_name = ''.join(c if c.isalnum() or c in '-_' else '_' for c in base_name)[:40]
    hash_suffix = hashlib.md5(file_name.encode()).hexdigest()[:8]
    return f"{safe_name}_{hash_suffix}"


def extract_document_type(file_name: str) -> str:
    """Extract document type from subfolder structure."""
    parts = file_name.split('/')
    if len(parts) >= 3:  # documents/TYPE/filename.pdf
        return parts[1].upper().replace(' ', '_')
    return 'OTHER'


def check_processing_threshold() -> tuple[bool, List[Any]]:
    """Check if we have enough documents to process."""
    # Get training config
    config_ref = db.collection('training_configs').document(CLASSIFIER_PROCESSOR_ID)
    config = config_ref.get().to_dict() or {}
    
    # Check for pending documents
    pending_docs = db.collection('processed_documents')\
        .where('processor_id', '==', CLASSIFIER_PROCESSOR_ID)\
        .where('status', '==', 'pending_labeling')\
        .limit(100)\
        .get()
    
    pending_list = list(pending_docs)
    pending_count = len(pending_list)
    
    # Check if processor has trained version
    has_trained_version = check_processor_has_version()
    
    if has_trained_version:
        # Incremental training threshold
        threshold = config.get('min_documents_for_incremental', 2)
    else:
        # Initial training threshold
        threshold = config.get('min_documents_for_initial_training', 3)
    
    logger.info(f"Pending: {pending_count}, Threshold: {threshold}, Has version: {has_trained_version}")
    
    return pending_count >= threshold, pending_list


def check_processor_has_version() -> bool:
    """Check if processor has any trained versions."""
    try:
        processor_path = f"projects/{PROJECT_ID}/locations/{LOCATION}/processors/{CLASSIFIER_PROCESSOR_ID}"
        request = documentai.ListProcessorVersionsRequest(parent=processor_path)
        versions = list(docai_client.list_processor_versions(request=request))
        return any(v.state == documentai.ProcessorVersion.State.DEPLOYED for v in versions)
    except:
        return False


def process_document_batch(documents: List[Any]) -> Optional[str]:
    """Process batch of documents: OCR, label, and import."""
    try:
        labeled_docs_created = []
        
        # Step 1: Process each document with OCR and create labeled JSON
        for doc_snapshot in documents:
            doc_data = doc_snapshot.to_dict()
            gcs_uri = doc_data['gcs_uri']
            document_type = doc_data['document_type']
            
            logger.info(f"Processing {gcs_uri} as {document_type}")
            
            # OCR the document
            ocr_result = process_with_ocr(gcs_uri)
            if not ocr_result:
                continue
            
            # Create labeled document
            labeled_doc = create_labeled_document(ocr_result, document_type, gcs_uri)
            
            # Save labeled document to GCS
            output_path = f"labeled_documents/{document_type}/{doc_data['document_id']}.json"
            if upload_labeled_document(labeled_doc, output_path):
                labeled_docs_created.append(output_path)
                
                # Update document status
                doc_snapshot.reference.update({
                    'status': 'labeled',
                    'labeled_path': f"gs://{BUCKET_NAME}/{output_path}",
                    'labeled_at': datetime.now(timezone.utc)
                })
        
        if not labeled_docs_created:
            logger.error("No documents were successfully labeled")
            return None
        
        logger.info(f"Labeled {len(labeled_docs_created)} documents")
        
        # Step 2: Import all labeled documents to Document AI
        import_operation = import_documents_to_processor()
        
        if import_operation:
            # Mark documents as imported
            for doc_snapshot in documents:
                if doc_snapshot.to_dict()['status'] == 'labeled':
                    doc_snapshot.reference.update({
                        'status': 'imported',
                        'import_operation': import_operation,
                        'imported_at': datetime.now(timezone.utc)
                    })
        
        return import_operation
        
    except Exception as e:
        logger.error(f"Batch processing error: {str(e)}", exc_info=True)
        return None


def process_with_ocr(gcs_uri: str) -> Optional[Dict]:
    """Process document with OCR processor."""
    try:
        # Read document content
        bucket_name = gcs_uri.split('/')[2]
        blob_name = '/'.join(gcs_uri.split('/')[3:])
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        content = blob.download_as_bytes()
        
        # Process with OCR
        request = documentai.ProcessRequest(
            name=f"projects/{PROJECT_ID}/locations/{LOCATION}/processors/{OCR_PROCESSOR_ID}",
            raw_document=documentai.RawDocument(
                content=content,
                mime_type="application/pdf"
            )
        )
        
        result = docai_client.process_document(request=request)
        return result.document
        
    except Exception as e:
        logger.error(f"OCR error for {gcs_uri}: {str(e)}")
        return None


def create_labeled_document(doc: Any, document_type: str, original_uri: str) -> Dict:
    """Create labeled document in Document AI format."""
    # Convert protobuf to dict properly
    pages = []
    for page in doc.pages:
        page_dict = {
            "pageNumber": page.page_number,
            "dimension": {
                "width": page.dimension.width,
                "height": page.dimension.height
            } if page.dimension else None
        }
        pages.append(page_dict)
    
    labeled_doc = {
        "mimeType": "application/pdf",
        "text": doc.text or "",
        "pages": pages,
        "uri": original_uri,
        "entities": [
            {
                "type": document_type,
                "mentionText": document_type,
                "confidence": 1.0,
                "textAnchor": {
                    "textSegments": [
                        {
                            "startIndex": "0",
                            "endIndex": str(len(document_type))
                        }
                    ]
                }
            }
        ]
    }
    
    return labeled_doc


def upload_labeled_document(labeled_doc: Dict, output_path: str) -> bool:
    """Upload labeled document JSON to GCS."""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(output_path)
        blob.upload_from_string(
            json.dumps(labeled_doc),
            content_type='application/json'
        )
        logger.info(f"Uploaded: gs://{BUCKET_NAME}/{output_path}")
        return True
    except Exception as e:
        logger.error(f"Upload error: {str(e)}")
        return False


def import_documents_to_processor() -> Optional[str]:
    """Import labeled documents to Document AI processor."""
    try:
        url = f"https://{LOCATION}-documentai.googleapis.com/v1beta3/projects/{PROJECT_ID}/locations/{LOCATION}/processors/{CLASSIFIER_PROCESSOR_ID}/dataset:importDocuments"
        
        # Use the Document AI client to make the request
        import google.auth
        from google.auth.transport.requests import Request as AuthRequest
        
        credentials, _ = google.auth.default()
        credentials.refresh(AuthRequest())
        
        import requests
        headers = {
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json",
            "X-Goog-User-Project": PROJECT_ID
        }
        
        data = {
            "batchDocumentsImportConfigs": [
                {
                    "batchInputConfig": {
                        "gcsPrefix": {
                            "gcsUriPrefix": f"gs://{BUCKET_NAME}/labeled_documents/"
                        }
                    },
                    "autoSplitConfig": {
                        "trainingSplitRatio": 0.8
                    }
                }
            ]
        }
        
        response = requests.post(url, headers=headers, json=data)
        
        if response.status_code == 200:
            operation_name = response.json().get('name')
            logger.info(f"Import started: {operation_name}")
            return operation_name
        else:
            logger.error(f"Import failed: {response.text}")
            return None
            
    except Exception as e:
        logger.error(f"Import error: {str(e)}", exc_info=True)
        return None


def trigger_training_workflow(import_operation: str):
    """Trigger workflow to monitor import and train."""
    try:
        parent = f"projects/{PROJECT_ID}/locations/{WORKFLOW_LOCATION}/workflows/{WORKFLOW_NAME}"
        
        execution = Execution(
            argument=json.dumps({
                'processor_id': CLASSIFIER_PROCESSOR_ID,
                'location': LOCATION,
                'import_operation': import_operation,
                'triggered_at': datetime.now(timezone.utc).isoformat()
            })
        )
        
        request = executions_v1.CreateExecutionRequest(
            parent=parent,
            execution=execution
        )
        
        response = workflow_execution_client.create_execution(request=request)
        logger.info(f"Workflow started: {response.name}")
        
    except Exception as e:
        logger.error(f"Workflow trigger error: {str(e)}", exc_info=True)