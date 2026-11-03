# Infra

A Pulumi program in Go that deploys the API in `backend/` to Google Cloud Run, against the Neon `main` branch. It enables the Cloud Run, Artifact Registry, Secret Manager, and IAM APIs, builds and pushes the image, stores the database URL in Secret Manager, and runs one public service named `aloft-api`. Health data never reaches it: the API holds the profile and the Crew only.

Stack config (`Pulumi.<stack>.yaml`) names the GCP project and holds the encrypted database URL, so git ignores it. Set it up on each machine with the steps below.

## Set up

1. Install Pulumi (`brew install pulumi`) and the Google Cloud CLI.
2. Start Docker. The build runs on your machine and targets linux/amd64.
3. Sign in:

   ```sh
   pulumi login
   gcloud auth application-default login
   ```

4. From `infra/`, create the stack and set its config:

   ```sh
   pulumi stack init prod
   pulumi config set gcp:project <project-id>
   pulumi config set aloft:neonAuthUrl <main branch Neon Auth URL>
   pulumi config set --secret aloft:databaseUrl <main branch pooled connection string>
   ```

   The pooled string is in the Neon console, or run `neonctl connection-string main --pooled`. The region defaults to `us-east4`, the closest to Neon's aws-us-east-1. Set `gcp:region` to change it.

## Deploy

```sh
make infra-preview
make infra-up
```

Each `up` that changes `backend/` pushes a new image and rolls a new revision, because the service runs the image by digest.

## After the first deploy

1. Read the URL with `pulumi stack output url`.
2. Check the service: `curl <url>/healthz` prints `ok`.
3. Put the URL in `ios/Config/Local.xcconfig` as `ALOFT_API_URL` for Release builds. Debug builds read that file too, so scope the line, and write `https:/$()/` in place of `https://` as the other xcconfig files do:

   ```
   ALOFT_API_URL[config=Release] = https:/$()/aloft-api-xxxx.us-east4.run.app
   ```

## Not managed here

Neon itself and the Neon Auth settings (the Apple provider, the SMTP sender, the trusted origin) are set in the Neon console. See decision 9 in [docs/decisions.md](../docs/decisions.md).
