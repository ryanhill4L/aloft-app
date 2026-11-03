# Infra

Terraform that deploys the API in `backend/` to Google Cloud Run, against the Neon `main` branch. It enables the Cloud Run, Artifact Registry, Secret Manager, and IAM APIs, builds and pushes the image, stores the database URL in Secret Manager, and runs one public service named `aloft-api`. Health data never reaches it: the API holds the profile and the Crew only.

The database URL is a write-only attribute, so it never lands in Terraform state. `terraform.tfvars` and `backend.hcl` name the GCP project and hold the URL, so git ignores them. Set them up on each machine with the steps below.

## Set up

1. Install Terraform 1.11 or later (`brew install hashicorp/tap/terraform`) and the Google Cloud CLI.
2. Start Docker. The build runs on your machine and targets linux/amd64.
3. Create a GCP project with billing on. Then sign in and point quota at it:

   ```sh
   gcloud auth application-default login
   gcloud auth application-default set-quota-project <project-id>
   ```

4. Create the state bucket once:

   ```sh
   gcloud storage buckets create gs://<project-id>-tfstate --project <project-id> --location us-east4 --uniform-bucket-level-access
   gcloud storage buckets update gs://<project-id>-tfstate --versioning
   ```

5. In `infra/`, write `backend.hcl`:

   ```hcl
   bucket = "<project-id>-tfstate"
   ```

   and `terraform.tfvars`:

   ```hcl
   project       = "<project-id>"
   neon_auth_url = "<main branch Neon Auth URL>"
   database_url  = "<main branch pooled connection string>"
   ```

   The pooled string is in the Neon console, or run `neonctl connection-string main --pooled`. The region defaults to `us-east4`, the closest to Neon's aws-us-east-1. Set `region` to change it.

6. Run `make infra-init`.

## Deploy

```sh
make infra-plan
make infra-up
```

Each `up` that changes `backend/` builds and pushes a new image and rolls a new revision, because the service runs the image by digest.

To change the database URL, edit it in `terraform.tfvars` and raise `database_url_version` (it defaults to 1). Terraform cannot see a write-only value change on its own.

## After the first deploy

1. Read the URL with `terraform output url`.
2. Check the service: `curl <url>/healthz` prints `ok`.
3. Put the URL in `ios/Config/Local.xcconfig` as `ALOFT_API_URL` for Release builds. Debug builds read that file too, so scope the line, and write `https:/$()/` in place of `https://` as the other xcconfig files do:

   ```
   ALOFT_API_URL[config=Release] = https:/$()/aloft-api-xxxx.us-east4.run.app
   ```

## Not managed here

Neon itself and the Neon Auth settings (the Apple provider, the SMTP sender, the trusted origin) are set in the Neon console. See decision 9 in [docs/decisions.md](../docs/decisions.md).
