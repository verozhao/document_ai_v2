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

