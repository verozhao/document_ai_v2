#!/bin/bash
# Automated Document AI Training Pipeline Deployment Script
# Updated version with OCR processor support

set -e

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-tetrix-462721}"
CLASSIFIER_PROCESSOR_ID="${DOCUMENT_AI_PROCESSOR_ID:-ddc065df69bfa3b5}"
OCR_PROCESSOR_ID="${OCR_PROCESSOR_ID:-2369784b09e9d56a}"
PROCESSOR_NAME="document_classifier_veronica"
DOCAI_LOCATION="us"
STORAGE_LOCATION="us"
CLOUD_LOCATION="us-central1"
FUNCTION_LOCATION="us-central1"
BUCKET_NAME="${GCS_BUCKET_NAME:-document-ai-test-veronica}"
FUNCTION_NAME="document-ai-service"
WORKFLOW_NAME="monitor-and-train"
SCHEDULER_JOB_NAME="document-ai-check-scheduler"

# Use existing service account
SERVICE_ACCOUNT="document-ai-service@${PROJECT_ID}.iam.gserviceaccount.com"

# Training configuration
MIN_DOCUMENTS_INITIAL="${MIN_DOCUMENTS_INITIAL:-3}"
MIN_DOCUMENTS_INCREMENTAL="${MIN_DOCUMENTS_INCREMENTAL:-2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local errors=0
    
    if [ -z "$PROJECT_ID" ]; then
        print_error "GCP_PROJECT_ID environment variable is not set"
        ((errors++))
    fi
    
    if [ -z "$CLASSIFIER_PROCESSOR_ID" ]; then
        print_error "DOCUMENT_AI_PROCESSOR_ID environment variable is not set"
        ((errors++))
    fi
    
    if [ -z "$OCR_PROCESSOR_ID" ]; then
        print_warning "OCR_PROCESSOR_ID not set, using default: 2369784b09e9d56a"
    fi
    
    # Check required files
    local required_files=("main.py" "requirements.txt" "monitor-and-train.yaml")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Required file not found: $file"
            ((errors++))
        fi
    done
    
    # Verify service account
    if ! gcloud iam service-accounts describe $SERVICE_ACCOUNT --project=$PROJECT_ID &> /dev/null; then
        print_error "Service account not found: $SERVICE_ACCOUNT"
        ((errors++))
    else
        print_status "Service account verified: $SERVICE_ACCOUNT"
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "Prerequisites check failed with $errors errors"
        exit 1
    fi
    
    gcloud config set project $PROJECT_ID
    print_status "Prerequisites check completed"
}

# Enable APIs
enable_apis() {
    print_info "Enabling required APIs..."
    
    APIs=(
        "documentai.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "workflows.googleapis.com"
        "cloudscheduler.googleapis.com"
        "firestore.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${APIs[@]}"; do
        gcloud services enable $api --quiet &
    done
    wait
    
    print_status "All APIs enabled"
}

# Create storage bucket
create_storage_bucket() {
    print_info "Setting up storage bucket..."
    
    if ! gsutil ls -b gs://$BUCKET_NAME &> /dev/null; then
        gsutil mb -p $PROJECT_ID -c STANDARD -l $STORAGE_LOCATION gs://$BUCKET_NAME
        print_status "Created bucket: gs://$BUCKET_NAME"
    else
        print_status "Bucket exists: gs://$BUCKET_NAME"
    fi
    
    # Grant service account access
    gsutil iam ch serviceAccount:$SERVICE_ACCOUNT:objectAdmin gs://$BUCKET_NAME
    print_status "Service account granted bucket access"
}

# Setup Firestore
setup_firestore() {
    print_info "Setting up Firestore..."
    
    # Create Firestore database if needed
    if ! gcloud firestore databases list --format="value(name)" | grep -q "(default)"; then
        gcloud firestore databases create --location=$CLOUD_LOCATION --type=firestore-native
        print_status "Created Firestore database"
    else
        print_status "Firestore database exists"
    fi
    
    # Initialize configuration
    cat > init_config.py << EOF
from google.cloud import firestore
from datetime import datetime, timezone

db = firestore.Client(project='$PROJECT_ID')

# Initialize training config
config_ref = db.collection('training_configs').document('$CLASSIFIER_PROCESSOR_ID')
config_ref.set({
    'processor_id': '$CLASSIFIER_PROCESSOR_ID',
    'processor_name': '$PROCESSOR_NAME',
    'ocr_processor_id': '$OCR_PROCESSOR_ID',
    'enabled': True,
    'min_documents_for_initial_training': $MIN_DOCUMENTS_INITIAL,
    'min_documents_for_incremental': $MIN_DOCUMENTS_INCREMENTAL,
    'created_at': datetime.now(timezone.utc),
    'updated_at': datetime.now(timezone.utc)
}, merge=True)

print("✓ Configuration initialized")
EOF

    python3 init_config.py
    rm init_config.py
    
    print_status "Firestore configured"
}

# Deploy Cloud Function
deploy_cloud_function() {
    print_info "Deploying Cloud Function..."
    
    # Check if function exists and delete if switching generations
    if gcloud functions describe $FUNCTION_NAME --region=$FUNCTION_LOCATION &> /dev/null 2>&1; then
        print_warning "Function already exists, updating..."
    fi
    
    # Ensure requirements.txt has necessary dependencies
    cat > requirements.txt << EOF
functions-framework==3.*
google-cloud-documentai==2.20.0
google-cloud-firestore==2.13.1
google-cloud-workflows==1.12.1
google-cloud-storage==2.10.0
requests==2.31.0
EOF
    
    # Deploy as 1st gen (compatible with existing deployment)
    gcloud functions deploy $FUNCTION_NAME \
        --runtime python39 \
        --trigger-resource $BUCKET_NAME \
        --trigger-event google.storage.object.finalize \
        --entry-point process_document_upload \
        --source . \
        --service-account $SERVICE_ACCOUNT \
        --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID,DOCUMENT_AI_PROCESSOR_ID=$CLASSIFIER_PROCESSOR_ID,OCR_PROCESSOR_ID=$OCR_PROCESSOR_ID,DOCUMENT_AI_LOCATION=$DOCAI_LOCATION,WORKFLOW_NAME=$WORKFLOW_NAME,GCS_BUCKET_NAME=$BUCKET_NAME" \
        --memory 1GB \
        --timeout 540s \
        --region $FUNCTION_LOCATION \
        --max-instances 10
    
    print_status "Cloud Function deployed"
}

# Deploy Workflow
deploy_workflow() {
    print_info "Deploying Workflow..."
    
    gcloud workflows deploy $WORKFLOW_NAME \
        --source=monitor-and-train.yaml \
        --location=$CLOUD_LOCATION \
        --service-account=$SERVICE_ACCOUNT
    
    print_status "Workflow deployed"
}

# Create scheduler (optional - for periodic checks)
create_scheduler_job() {
    print_info "Creating optional scheduler job..."
    
    if gcloud scheduler jobs describe $SCHEDULER_JOB_NAME --location=$CLOUD_LOCATION &> /dev/null; then
        gcloud scheduler jobs delete $SCHEDULER_JOB_NAME --location=$CLOUD_LOCATION --quiet
    fi
    
    # Skip scheduler for now - uploads will trigger processing
    print_warning "Skipping scheduler job - processing triggered by uploads"
}

# Validate deployment
validate_deployment() {
    print_info "Validating deployment..."
    
    local errors=0
    
    # Check Cloud Function
    if gcloud functions describe $FUNCTION_NAME --region=$FUNCTION_LOCATION &> /dev/null; then
        print_status "Cloud Function: Deployed"
    else
        print_error "Cloud Function: Not found"
        ((errors++))
    fi
    
    # Check Workflow
    if gcloud workflows describe $WORKFLOW_NAME --location=$CLOUD_LOCATION &> /dev/null; then
        print_status "Workflow: Deployed"
    else
        print_error "Workflow: Not found"
        ((errors++))
    fi
    
    # Check Firestore
    if gcloud firestore databases describe --database="(default)" &> /dev/null; then
        print_status "Firestore: Available"
    else
        print_error "Firestore: Not available"
        ((errors++))
    fi
    
    return $errors
}

# Show next steps
show_next_steps() {
    echo
    echo -e "${BLUE}${BOLD}=== Deployment Complete! ===${NC}"
    echo
    echo -e "${GREEN}✓ All components deployed successfully${NC}"
    echo
    echo -e "${BOLD}Configuration:${NC}"
    echo "  • Classifier Processor: $CLASSIFIER_PROCESSOR_ID"
    echo "  • OCR Processor: $OCR_PROCESSOR_ID"
    echo "  • Bucket: gs://$BUCKET_NAME"
    echo "  • Initial training threshold: $MIN_DOCUMENTS_INITIAL documents"
    echo "  • Incremental training threshold: $MIN_DOCUMENTS_INCREMENTAL documents"
    echo
    echo -e "${BOLD}Usage:${NC}"
    echo
    echo "1. Upload documents to auto-label based on folder:"
    echo "   gsutil cp document.pdf gs://$BUCKET_NAME/documents/CAPITAL_CALL/"
    echo "   gsutil cp statement.pdf gs://$BUCKET_NAME/documents/FINANCIAL_STATEMENT/"
    echo
    echo "2. Batch upload entire folders:"
    echo "   gsutil -m cp -r local_folder/* gs://$BUCKET_NAME/documents/"
    echo
    echo "3. Monitor processing:"
    echo "   gcloud functions logs read $FUNCTION_NAME --region=$FUNCTION_LOCATION --follow"
    echo
    echo "4. Check Firestore status:"
    echo "   https://console.cloud.google.com/firestore/data/processed_documents?project=$PROJECT_ID"
    echo
    echo -e "${YELLOW}The pipeline will automatically:${NC}"
    echo "  • Detect new uploads"
    echo "  • Process with OCR when threshold is met"
    echo "  • Create labeled documents"
    echo "  • Import to Document AI"
    echo "  • Start training after import completes"
    echo
}

# Main
main() {
    echo -e "${BLUE}${BOLD}=== Document AI Auto-Training Pipeline Deployment ===${NC}"
    echo "Project: $PROJECT_ID"
    echo
    
    check_prerequisites
    enable_apis
    create_storage_bucket
    setup_firestore
    deploy_cloud_function
    deploy_workflow
    create_scheduler_job
    
    if validate_deployment; then
        show_next_steps
    else
        print_error "Deployment validation failed"
        exit 1
    fi
}

main