# Azure

This app runs on Azure Container Apps as `rep-tell`: https://rep-tell.lemonfield-c4c1d145.centralindia.azurecontainerapps.io

## How a change goes live

1. Push to `main`.
2. `.github/workflows/azure.yml` builds the image and uploads it to
   `purvashared82aaf9d4.azurecr.io/rep-tell`.
3. [RishabhWDB/purva-platform](https://github.com/RishabhWDB/purva-platform) deploys it,
   usually within 5-15 minutes, and checks it's healthy. If it isn't, the previous version
   stays live.

The website is a separate Static Web App (`rep-tell-web`), published by
`.github/workflows/azure-frontend.yml` on every push that changes it.

## Files

| File | What |
|---|---|
| `.github/workflows/azure.yml` | Builds and uploads the image |
| `.github/workflows/azure-frontend.yml` | Builds and publishes the website |
| `deploy/staticwebapp.config.json` | Website routing |
| `deploy/Dockerfile` | How the image is built |
| `deploy/azure-deploy.conf` | Names and IDs the workflows read |

## Changing settings

Environment variables, secrets, size and number of copies are managed by the platform
owner, not from this repo. Ask them for any change.

The setup scripts that used to live in `deploy/` were removed on 2026-11-23; they are in
this repo's git history.
