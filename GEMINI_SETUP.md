# Gemini 2.5 Flash Setup Guide

This guide will help you set up Google Vertex AI Gemini 2.5 Flash for your LiveAI Chat application.

## Prerequisites

1. A Google Cloud Project with Vertex AI API enabled
2. A service account with Vertex AI permissions

## Step 1: Enable Vertex AI API

1. Go to the [Google Cloud Console](https://console.cloud.google.com)
2. Select your project: `gen-lang-client-0910640178` (or create a new one)
3. Enable the Vertex AI API:
   ```bash
   gcloud services enable aiplatform.googleapis.com
   ```

## Step 2: Create a Service Account

1. Create a service account:
   ```bash
   gcloud iam service-accounts create gemini-chat-service \
     --description="Service account for Gemini Chat" \
     --display-name="Gemini Chat Service" \
     --project=gen-lang-client-0910640178
   ```

2. Grant necessary permissions:
   ```bash
   gcloud projects add-iam-policy-binding gen-lang-client-0910640178 \
     --member="serviceAccount:gemini-chat-service@gen-lang-client-0910640178.iam.gserviceaccount.com" \
     --role="roles/aiplatform.user"
   ```

3. Create and download a service account key:
   ```bash
   gcloud iam service-accounts keys create ~/gemini-service-account.json \
     --iam-account=gemini-chat-service@gen-lang-client-0910640178.iam.gserviceaccount.com
   ```

## Step 3: Configure Environment Variables

You have two authentication options:

### Option A: Using Service Account Key File (Recommended for Development)

Export the following environment variables:

```bash
export VERTEXAI_PROJECT="gen-lang-client-0910640178"
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/gemini-service-account.json"
export VERTEXAI_LOCATION="europe-west1"     # Optional: defaults to europe-west1
export GEMINI_MODEL="gemini-2.5-flash"      # Optional: defaults to gemini-2.5-flash
```

### Option B: Using Service Account JSON as Environment Variable

```bash
export VERTEXAI_PROJECT="gen-lang-client-0910640178"
export GOOGLE_SERVICE_ACCOUNT_JSON='{"type": "service_account", "project_id": "gen-lang-client-0910640178", ...}'
export VERTEXAI_LOCATION="europe-west1"     # Optional
export GEMINI_MODEL="gemini-2.5-flash"      # Optional
```

## Step 4: Test the Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Set your environment variables (copy from `example.env`):
   ```bash
   export VERTEXAI_PROJECT="gen-lang-client-0910640178"
   export VERTEXAI_LOCATION="europe-west1"
   export GOOGLE_APPLICATION_CREDENTIALS="./gemini-service-account.json"
   ```

3. Start the application:
   ```bash
   mix phx.server
   ```

4. Visit `http://localhost:4000` and send a message to test Gemini integration.

## Quick Setup (If You Already Have gcloud CLI Configured)

```bash
# Set your environment variables
export VERTEXAI_PROJECT="gen-lang-client-0910640178"
export VERTEXAI_LOCATION="europe-west1"

# Use application default credentials
gcloud auth application-default login

# Start the app
mix phx.server
```

## Supported Models

- `gemini-2.5-flash` (default, recommended)
- `gemini-2.5-pro`
- `gemini-1.5-flash` (legacy)
- `gemini-1.5-pro` (legacy)

## Supported Regions

- `europe-west1` (default for this project)
- `us-central1`
- `us-east1`
- `us-east4`
- `us-west1`
- `europe-west4`
- `asia-northeast1`

## Troubleshooting

### Authentication Errors

If you see authentication errors:

1. Verify your service account key file exists and is valid
2. Check that the `VERTEXAI_PROJECT` environment variable is set correctly to `gen-lang-client-0910640178`
3. Ensure the Vertex AI API is enabled in your project
4. Verify your service account has the `roles/aiplatform.user` role

### API Errors

If you get API-related errors:

1. Check that your project has Vertex AI API enabled
2. Verify your chosen region supports Gemini models
3. Check the application logs for detailed error messages

### Rate Limiting

Gemini 2.5 Flash has the following default limits:
- 1500 requests per minute
- 1M tokens per minute

If you hit rate limits, consider:
- Adding retry logic with exponential backoff
- Reducing the request frequency
- Upgrading your quota in Google Cloud Console

## Production Deployment

For production deployment:

1. **Never** commit service account keys to version control
2. Use Google Cloud's Workload Identity if deploying to GKE
3. Use environment variables for sensitive configuration
4. Consider using Google Secret Manager for storing keys

## Security Best Practices

1. Rotate service account keys regularly
2. Use least-privilege IAM roles
3. Monitor API usage and set up billing alerts
4. Enable audit logging for Vertex AI API calls