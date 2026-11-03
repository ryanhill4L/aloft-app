# Infra

Terraform that deploys the API in `backend/` to Google Cloud Run, against the Neon `main` branch. It enables the Cloud Run, Artifact Registry, Secret Manager, and IAM APIs, builds and pushes the image, lets the API read the database URL from Secret Manager, and runs one public service named `aloft-api`. Health data never reaches it: the API holds the profile and the Crew only.

You put the database URL into Secret Manager yourself with `gcloud`. Terraform only refers to the secret by name, so the URL never sits in a file, in Terraform state, or in a plan. `terraform.tfvars` and `backend.hcl` name the GCP project, so git ignores them. Set them up on each machine with the steps below.

## Set up

1. Install Terraform 1.10 or later (`brew install hashicorp/tap/terraform`) and the Google Cloud CLI.
2. Start Docker. `infra-up` runs `docker buildx build --push` on your machine for linux/amd64, after a `docker login` to Artifact Registry with a short-lived token.
3. Create a GCP project with billing on. Then sign in (the CLI and the application default credentials Terraform uses are separate logins) and point both at it:

   ```sh
   gcloud auth login
   gcloud config set project <project-id>
   gcloud auth application-default login
   gcloud auth application-default set-quota-project <project-id>
   ```

4. Create the state bucket once:

   ```sh
   gcloud storage buckets create gs://<project-id>-tfstate --project <project-id> --location us-east4 --uniform-bucket-level-access
   gcloud storage buckets update gs://<project-id>-tfstate --versioning
   ```

5. Store the database URL. Copy the Neon `main` branch's pooled connection string (Neon console, Connect, with connection pooling on), then pipe it from the clipboard so it stays out of your shell history:

   ```sh
   gcloud services enable secretmanager.googleapis.com
   pbpaste | gcloud secrets create database-url --replication-policy automatic --data-file -
   ```

6. In `infra/`, write `backend.hcl`:

   ```hcl
   bucket = "<project-id>-tfstate"
   ```

   and `terraform.tfvars`:

   ```hcl
   project       = "<project-id>"
   neon_auth_url = "<main branch Neon Auth URL>"
   ```

   The region defaults to `us-east4`, the closest to Neon's aws-us-east-1. Set `region` to change it.

7. Run `make infra-init`.

## Deploy

```sh
make infra-plan
make infra-up
```

Each `up` that changes `backend/` builds and pushes a new image and rolls a new revision, because the service runs the image by digest.

To change the database URL, add a version and start a new revision so running instances pick it up:

```sh
pbpaste | gcloud secrets versions add database-url --data-file -
gcloud run services update aloft-api --region us-east4 --update-labels rotated=$(date +%s)
```

## After the first deploy

1. Read the URL with `terraform output url`.
2. Check the service: `curl <url>/healthz` prints `ok`.
3. Put the URL in `ios/Config/Local.xcconfig` as `ALOFT_API_URL` for Release builds. Debug builds read that file too, so scope the line, and write `https:/$()/` in place of `https://` as the other xcconfig files do:

   ```
   ALOFT_API_URL[config=Release] = https:/$()/aloft-api-xxxx.us-east4.run.app
   ```

## Not managed here

Neon itself and the Neon Auth settings (the Apple provider, the SMTP sender, the trusted origin) are set in the Neon console. See decision 9 in [docs/decisions.md](../docs/decisions.md).
