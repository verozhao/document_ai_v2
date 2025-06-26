"""Automated Document AI Training Pipeline Deployment Script"""

set -e

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-tetrix-462721}"
PROCESSOR_ID="${DOCUMENT_AI_PROCESSOR_ID:-ddc065df69bfa3b5}"
PROCESSOR_NAME="${PROCESSOR_NAME:-document_classifier_veronica}"
DOCAI_LOCATION="${DOCUMENT_AI_LOCATION:-us}"
STORAGE_LOCATION="${STORAGE_LOCATION:-us}"
CLOUD_LOCATION="${CLOUD_LOCATION:-us-central1}"
FUNCTION_LOCATION="${FUNCTION_LOCATION:-us-central1}"
APP_ENGINE_LOCATION="${APP_ENGINE_LOCATION:-us-central}"
BUCKET_NAME="${GCS_BUCKET_NAME:-document-ai-test-veronica}"
FUNCTION_NAME="${FUNCTION_NAME:-document-ai-service}"
WORKFLOW_NAME="${WORKFLOW_NAME:-workflow-1-veronica}"
SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-document-ai-training-scheduler}"

SERVICE_ACCOUNT="document-ai-service@${PROJECT_ID}.iam.gserviceaccount.com"

# Training configuration
MIN_DOCUMENTS_INITIAL="${MIN_DOCUMENTS_INITIAL:-3}"
MIN_DOCUMENTS_INCREMENTAL="${MIN_DOCUMENTS_INCREMENTAL:-2}"
MIN_ACCURACY_DEPLOYMENT="${MIN_ACCURACY_DEPLOYMENT:-0}"

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

# Enhanced prerequisites check
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local errors=0
    
    # Environment variables
    if [ -z "$PROJECT_ID" ]; then
        print_error "GCP_PROJECT_ID environment variable is not set"
        ((errors++))
    fi
    
    if [ -z "$PROCESSOR_ID" ]; then
        print_error "DOCUMENT_AI_PROCESSOR_ID environment variable is not set"
        ((errors++))
    fi
    
    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed"
        ((errors++))
    else
        # Check if authenticated
        if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
            print_error "Not authenticated with gcloud. Run: gcloud auth login"
            ((errors++))
        fi
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        ((errors++))
    fi
    
    # Check required files training-workflow.yaml
    local required_files=("main.py" "requirements.txt" "monitor-and-train.yaml")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Required file not found: $file"
            ((errors++))
        fi
    done
    
    # Verify service account exists
    if ! gcloud iam service-accounts describe $SERVICE_ACCOUNT --project=$PROJECT_ID &> /dev/null; then
        print_error "Service account not found: $SERVICE_ACCOUNT"
        print_info "Please ensure the service account exists with proper permissions"
        ((errors++))
    else
        print_status "Service account verified: $SERVICE_ACCOUNT"
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "Prerequisites check failed with $errors errors"
        exit 1
    fi
    
    # Set project
    gcloud config set project $PROJECT_ID
    
    print_status "Prerequisites check completed"
}

# Enable required APIs with progress
enable_apis() {
    print_info "Enabling required APIs..."
    
    APIs=(
        "documentai.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "workflows.googleapis.com"
        "cloudscheduler.googleapis.com"
        "pubsub.googleapis.com"
        "firestore.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "appengine.googleapis.com"
    )
    
    local total=${#APIs[@]}
    local current=0
    
    for api in "${APIs[@]}"; do
        ((current++))
        echo -ne "\r  Enabling APIs: [$current/$total] $api"
        if gcloud services enable $api --quiet 2>/dev/null; then
            echo -ne "\r  ${GREEN}✓${NC} Enabled: $api \n"
        else
            echo -ne "\r  ${YELLOW}!${NC} Already enabled: $api \n"
        fi
    done
    
    print_status "All APIs enabled successfully"
}

# Create GCS bucket
create_storage_bucket() {
    print_info "Checking GCS bucket..."
    
    if gsutil ls -b gs://$BUCKET_NAME &> /dev/null; then
        print_status "Bucket $BUCKET_NAME exists"
    else
        gsutil mb -p $PROJECT_ID -c STANDARD -l $STORAGE_LOCATION gs://$BUCKET_NAME
        print_status "Created bucket: gs://$BUCKET_NAME"
    fi
    
    # Verify service account has access
    gsutil iam ch serviceAccount:$SERVICE_ACCOUNT:objectViewer,objectCreator gs://$BUCKET_NAME
    print_status "Service account granted bucket access"
}

# Create Pub/Sub topics
create_pubsub_topics() {
    print_info "Creating Pub/Sub topics..."
    
    topics=("document-ai-training" "document-ai-notifications")
    
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe $topic &> /dev/null; then
            print_warning "Topic $topic already exists"
        else
            gcloud pubsub topics create $topic
            print_status "Created topic: $topic"
        fi
    done
}

# Enhanced Firestore setup
setup_firestore() {
    print_info "Setting up Firestore..."
    
    # Create Firestore database if it doesn't exist
    if ! gcloud firestore databases list --format="value(name)" | grep -q "projects/$PROJECT_ID/databases/(default)"; then
        print_info "Creating Firestore database..."
        gcloud firestore databases create --location=$CLOUD_LOCATION --type=firestore-native
        print_status "Created Firestore database"
        sleep 10
    else
        print_warning "Firestore database already exists"
    fi
    
    # Initialize configuration with environment variables
    print_info "Initializing Firestore configuration..."
    
    cat > init_firestore_config.py << EOF
import os
from google.cloud import firestore
from datetime import datetime, timezone

project_id = '$PROJECT_ID'
processor_id = '$PROCESSOR_ID'
processor_name = '$PROCESSOR_NAME'

db = firestore.Client(project=project_id)

# Initialize training config
config_ref = db.collection('training_configs').document(processor_id)
config_data = {
    'processor_id': processor_id,
    'processor_name': processor_name,
    'enabled': True,
    'min_documents_for_initial_training': $MIN_DOCUMENTS_INITIAL,
    'min_documents_for_incremental': $MIN_DOCUMENTS_INCREMENTAL,
    'min_accuracy_for_deployment': $MIN_ACCURACY_DEPLOYMENT,
    'check_interval_minutes': 60,
    'auto_deploy': True,
    'document_types': [
        'CAPITAL_CALL',
        'DISTRIBUTION_NOTICE',
        'FINANCIAL_STATEMENT',
        'FINANCIAL_STATEMENT_AND_PCAP',
        'INVESTMENT_OVEVIEW',
        'INVESTOR_MEMOS',
        'INVESTOR_PRESENTATION',
        'INVESTOR_STATEMENT',
        'LEGAL',
        'MANAGEMENT_COMMENTARY',
        'PCAP_STATEMENT',
        'PORTFOLIO_SUMMARY',
        'PORTFOLIO_SUMMARY_AND_PCAP',
        'TAX',
        'OTHER'
    ],
    'created_at': datetime.now(timezone.utc),
    'updated_at': datetime.now(timezone.utc)
}

config_ref.set(config_data, merge=True)
print(f"Initialized training config for processor {processor_name}")

# Create indexes by adding and removing placeholder documents
collections = ['processed_documents', 'training_batches']
for collection in collections:
    placeholder_ref = db.collection(collection).document('_placeholder_')
    placeholder_ref.set({
        'processor_id': processor_id,
        'created_at': datetime.now(timezone.utc),
        '_placeholder': True
    })
    placeholder_ref.delete()
    print(f"Initialized collection: {collection}")
EOF

    python3 init_firestore_config.py
    rm init_firestore_config.py
    
    print_status "Firestore setup completed"
}

# Deploy Cloud Function with configuration
deploy_cloud_function() {
    print_info "Deploying Cloud Function..."
    
    # Create deployment directory with clean structure
    DEPLOY_DIR=$(mktemp -d)
    cp main.py $DEPLOY_DIR/
    cp requirements.txt $DEPLOY_DIR/
    
    # Ensure requirements.txt has all dependencies
    cat > $DEPLOY_DIR/requirements.txt << EOF
google-cloud-documentai==2.20.0
google-cloud-firestore==2.13.1
google-cloud-workflows==1.12.1
google-cloud-storage==2.10.0
functions-framework==3.*
EOF
    
    # Deploy with environment variables
    gcloud functions deploy $FUNCTION_NAME \
        --runtime python39 \
        --trigger-resource $BUCKET_NAME \
        --trigger-event google.storage.object.finalize \
        --entry-point process_document_upload \
        --source $DEPLOY_DIR \
        --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID,DOCUMENT_AI_PROCESSOR_ID=$PROCESSOR_ID,DOCUMENT_AI_LOCATION=$DOCAI_LOCATION,WORKFLOW_NAME=$WORKFLOW_NAME,GCS_BUCKET_NAME=$BUCKET_NAME,PROCESSOR_NAME=$PROCESSOR_NAME,MIN_DOCUMENTS_INITIAL=$MIN_DOCUMENTS_INITIAL,MIN_DOCUMENTS_INCREMENTAL=$MIN_DOCUMENTS_INCREMENTAL" \
        --memory 1GB \
        --timeout 540s \
        --region $FUNCTION_LOCATION \
        --service-account $SERVICE_ACCOUNT \
        --max-instances 10 \
        --no-gen2
    
    rm -rf $DEPLOY_DIR
    
    print_status "Cloud Function deployed successfully"
}

# Deploy Workflow
deploy_workflow() {
    print_info "Deploying Workflow..."
    
    # Ensure custom service account has necessary permissions
    print_info "Deploying workflow with custom service account: $SERVICE_ACCOUNT"
    
    # Deploy workflow using the custom service account
    gcloud workflows deploy $WORKFLOW_NAME \
        --source=monitor-and-train.yaml \
        --location=$CLOUD_LOCATION \
        --service-account=$SERVICE_ACCOUNT
    
    print_status "Workflow deployed successfully"
}

# Create Cloud Scheduler job
create_scheduler_job() {
    print_info "Setting up Cloud Scheduler..."
    # # Initialize App Engine
    # if ! gcloud app describe &> /dev/null; then
    #     print_info "Initializing App Engine (required for Cloud Scheduler)..."
    #     CREATE_OUTPUT=$(gcloud app create --region=$APP_ENGINE_LOCATION 2>&1)
    #     if echo "$CREATE_OUTPUT" | grep -q "already contains an App Engine application"; then
    #         print_warning "App Engine already exists. Skipping creation."
    #     elif ! gcloud app describe &> /dev/null; then
    #         print_error "Failed to create App Engine and it does not exist. Exiting."
    #         exit 1
    #     fi
    #     sleep 10
    # else
    #     print_warning "App Engine already exists. Skipping creation."
    # fi

    # Delete existing job if it exists
    if gcloud scheduler jobs describe $SCHEDULER_JOB_NAME --location=$CLOUD_LOCATION &> /dev/null; then
        print_warning "Deleting existing scheduler job..."
        gcloud scheduler jobs delete $SCHEDULER_JOB_NAME --location=$CLOUD_LOCATION --quiet
    fi
    # Create new scheduler job
    gcloud scheduler jobs create pubsub $SCHEDULER_JOB_NAME \
        --schedule="0 */6 * * *" \
        --topic=document-ai-training \
        --message-body="{\"action\":\"check_training\",\"processor_id\":\"$PROCESSOR_ID\"}" \
        --location=$CLOUD_LOCATION \
        --time-zone="UTC"
    print_status "Created scheduler job: $SCHEDULER_JOB_NAME (runs every 6 hours)"
}

# Comprehensive deployment validation
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
        print_status "Firestore: Configured"
    else
        print_error "Firestore: Not configured"
        ((errors++))
    fi
    
    # Check bucket
    if gsutil ls -b gs://$BUCKET_NAME &> /dev/null; then
        print_status "GCS Bucket: Available"
    else
        print_error "GCS Bucket: Not found"
        ((errors++))
    fi
    
    # Check recent function logs for errors
    print_info "Checking for recent errors..."
    ERROR_COUNT=$(gcloud functions logs read $FUNCTION_NAME --region=$FUNCTION_LOCATION --limit=20 --format=json 2>/dev/null | grep -c '"severity":"ERROR"' || echo "0")
    
    if [ "$ERROR_COUNT" -gt 0 ]; then
        print_warning "Found $ERROR_COUNT errors in recent logs"
    else
        print_status "No recent errors in function logs"
    fi
    
    return $errors
}

# Display next steps
show_next_steps() {
    echo
    echo -e "${BLUE}${BOLD}=== Deployment Complete! ===${NC}"
    echo
    echo -e "${GREEN}✓ All components deployed successfully${NC}"
    echo
    echo -e "${BOLD}Service Account:${NC} $SERVICE_ACCOUNT"
    echo -e "${BOLD}Processor:${NC} $PROCESSOR_NAME ($PROCESSOR_ID)"
    echo -e "${BOLD}Bucket:${NC} gs://$BUCKET_NAME"
    echo
    echo -e "${BOLD}Next Steps:${NC}"
    echo
    echo "1. Upload documents to trigger processing:"
    echo "   ${BLUE}# Upload to specific document type folder for auto-labeling${NC}"
    echo "   gsutil cp capital_call.pdf gs://$BUCKET_NAME/documents/CAPITAL_CALL/"
    echo "   gsutil cp financial_stmt.pdf gs://$BUCKET_NAME/documents/FINANCIAL_STATEMENT/"
    echo
    echo "2. Monitor the pipeline:"
    echo "   ${BLUE}# Watch function logs in real-time${NC}"
    echo "   gcloud functions logs read $FUNCTION_NAME --region=$FUNCTION_LOCATION --follow"
    echo
    echo "   ${BLUE}# Check function logs for errors${NC}"
    echo "   gcloud functions logs read $FUNCTION_NAME --region=$FUNCTION_LOCATION --filter='severity=ERROR' --limit=10"
    echo
    echo "3. Check pipeline status:"
    echo "   ${BLUE}# Run diagnostics${NC}"
    echo "   python3 diagnose-training-issues.py"
    echo
    echo "4. View Firestore data:"
    echo "   ${BLUE}# Open Firestore console${NC}"
    echo "   https://console.cloud.google.com/firestore/data/processed_documents?project=$PROJECT_ID"
    echo
    echo "5. Manual workflow trigger (for testing):"
    echo "   gcloud workflows execute $WORKFLOW_NAME --location=$CLOUD_LOCATION \\"
    echo "     --data='{\"processor_id\":\"$PROCESSOR_ID\",\"training_type\":\"initial\"}'"
    echo
    echo -e "${YELLOW}Training will trigger automatically when:${NC}"
    echo "  • Initial training: $MIN_DOCUMENTS_INITIAL labeled documents"
    echo "  • Incremental training: $MIN_DOCUMENTS_INCREMENTAL new labeled documents"
    echo
}


main() {
    echo -e "${BLUE}${BOLD}=== Document AI Automated Training Pipeline Deployment ===${NC}"
    echo "Project: $PROJECT_ID"
    echo "Service Account: $SERVICE_ACCOUNT"
    echo "Processor: $PROCESSOR_NAME"
    echo
    
    check_prerequisites
    enable_apis
    create_storage_bucket
    create_pubsub_topics
    setup_firestore
    deploy_cloud_function
    deploy_workflow
    create_scheduler_job
    
    if validate_deployment; then
        show_next_steps
    else
        print_error "Deployment validation failed. Please check the errors above."
        exit 1
    fi
}

main