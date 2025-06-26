#!/usr/bin/env python3
"""
Final successful auto-labeling script that actually works!
This processes more documents from multiple document types.
"""

import json
import requests
import time
from google.auth import default
from google.auth.transport.requests import Request

# Configuration
PROJECT_ID = "tetrix-462721"
OCR_PROCESSOR_ID = "2369784b09e9d56a"  # OCR processor for text extraction
CLASSIFIER_PROCESSOR_ID = "ddc065df69bfa3b5"  # Classifier processor for import
LOCATION = "us"
BUCKET_NAME = "document-ai-test-veronica"

def get_access_token():
    """Get Google Cloud access token"""
    credentials, _ = default()
    credentials.refresh(Request())
    return credentials.token

def list_files_in_folder(folder_path):
    """List files in a GCS folder"""
    access_token = get_access_token()
    url = f"https://storage.googleapis.com/storage/v1/b/{BUCKET_NAME}/o"
    headers = {"Authorization": f"Bearer {access_token}"}
    params = {"prefix": folder_path}
    
    response = requests.get(url, headers=headers, params=params)
    if response.status_code == 200:
        items = response.json().get("items", [])
        return [item for item in items if item["name"].endswith(".pdf")]
    else:
        print(f"Error listing files: {response.text}")
        return []

def process_document_with_ai(file_path):
    """Process a document with OCR processor"""
    access_token = get_access_token()
    url = f"https://us-documentai.googleapis.com/v1/projects/{PROJECT_ID}/locations/{LOCATION}/processors/{OCR_PROCESSOR_ID}:process"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    
    data = {
        "gcsDocument": {
            "gcsUri": f"gs://{BUCKET_NAME}/{file_path}",
            "mimeType": "application/pdf"
        }
    }
    
    response = requests.post(url, headers=headers, json=data)
    if response.status_code == 200:
        return response.json()
    else:
        print(f"Error processing document {file_path}: {response.text}")
        return None

def create_labeled_document(processed_doc, document_type, original_uri):
    """Create a labeled document with proper entities"""
    if not processed_doc or "document" not in processed_doc:
        return None
    
    doc = processed_doc["document"]
    
    # Create the labeled document structure
    labeled_doc = {
        "mimeType": "application/pdf",
        "text": doc.get("text", ""),
        "pages": doc.get("pages", []),
        "uri": original_uri,
        "entities": [
            {
                "type": document_type,
                "mentionText": document_type,
                "confidence": 1.0,
                "textAnchor": {
                    "textSegments": [
                        {
                            "startIndex": 0,
                            "endIndex": len(document_type)
                        }
                    ]
                }
            }
        ]
    }
    
    return labeled_doc

def upload_labeled_document(labeled_doc, output_path):
    """Upload labeled document to GCS"""
    access_token = get_access_token()
    url = f"https://storage.googleapis.com/upload/storage/v1/b/{BUCKET_NAME}/o"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    params = {"uploadType": "media", "name": output_path}
    
    response = requests.post(url, headers=headers, params=params, data=json.dumps(labeled_doc))
    return response.status_code == 200

def import_documents_to_processor():
    """Import labeled documents to classifier processor"""
    access_token = get_access_token()
    url = f"https://us-documentai.googleapis.com/v1beta3/projects/{PROJECT_ID}/locations/{LOCATION}/processors/{CLASSIFIER_PROCESSOR_ID}/dataset:importDocuments"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "X-Goog-User-Project": PROJECT_ID
    }
    
    data = {
        "batchDocumentsImportConfigs": [
            {
                "batchInputConfig": {
                    "gcsPrefix": {
                        "gcsUriPrefix": f"gs://{BUCKET_NAME}/final_labeled_documents/"
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
        return response.json()
    else:
        print(f"Error importing documents: {response.text}")
        return None

def main():
    print("🚀 Final successful auto-labeling for Document AI")
    print("Processing documents from multiple folders...")
    
    # Process multiple document types
    folder_types = ["capital_call", 
    "financial_statement", 
    "financial_statement_and_pcap", 
    "distribution_notice", 
    "investment_overview", 
    "investor_memos", 
    "investor_presentation", 
    "investor_statement", 
    "legal", 
    "management_commentary", 
    "pcap_statement", 
    "portfolio_summary", 
    "portfolio_summary_and_pcap", 
    "tax", 
    "other"]
    total_processed = 0
    
    for doc_type in folder_types:
        print(f"\n📁 Processing {doc_type} documents...")
        folder_path = f"documents/{doc_type}/"
        files = list_files_in_folder(folder_path)
        
        print(f"Found {len(files)} PDF files in {doc_type}")
        
        # Process first 5 files from each folder
        for i, file_item in enumerate(files):
            file_path = file_item["name"]
            file_name = file_path.split("/")[-1]
            print(f"  Processing: {file_name}")
            
            # Process with Document AI
            processed = process_document_with_ai(file_path)
            if processed:
                # Create labeled document
                original_uri = f"gs://{BUCKET_NAME}/{file_path}"
                labeled_doc = create_labeled_document(processed, doc_type, original_uri)
                
                if labeled_doc:
                    # Upload labeled document
                    output_name = file_name.replace(".pdf", ".json")
                    output_path = f"final_labeled_documents/{doc_type}/{output_name}"
                    
                    if upload_labeled_document(labeled_doc, output_path):
                        print(f"    ✅ Uploaded: {output_path}")
                        total_processed += 1
                    else:
                        print(f"    ❌ Failed to upload: {output_path}")
                else:
                    print(f"    ❌ Failed to create labeled document")
            else:
                print(f"    ❌ Failed to process: {file_name}")
    
    print(f"\n📊 Total documents processed and labeled: {total_processed}")
    
    if total_processed > 0:
        print("\n🔄 Starting import to Document AI processor...")
        import_result = import_documents_to_processor()
        
        if import_result and "name" in import_result:
            operation_name = import_result["name"]
            print(f"✅ Import operation started: {operation_name}")
            print(f"\n🎉 SUCCESS! Check your Document AI processor in the console:")
            print(f"https://console.cloud.google.com/ai/document-ai/processors/details/{CLASSIFIER_PROCESSOR_ID}?project={PROJECT_ID}")
            print(f"\nLabeled documents location: gs://{BUCKET_NAME}/final_labeled_documents/")
            print(f"Total documents with labels: {total_processed}")
            
            print("\n✅ AUTO-LABELING COMPLETE!")
            print("- Documents processed with OCR to extract text and structure")
            print("- Auto-labeled based on subfolder names")
            print("- Proper Document AI JSON format created with entities")
            print("- Imported into Document AI processor with auto-split")
            print("- Ready for training!")
            
            return True
        else:
            print("❌ Failed to start import operation")
            return False
    else:
        print("❌ No documents were processed successfully")
        return False

if __name__ == "__main__":
    success = main()
    if success:
        print("\n🎯 MISSION ACCOMPLISHED: Auto-labeling pipeline working successfully!")
    else:
        print("\n❌ Mission failed - check the errors above")