# Deploying Rep-Tell to Azure

Rep-Tell has two parts, and both deploy automatically on every push to `main`:

- **The backend** (`backend/`, the FastAPI API) runs on **Azure Container
  Apps**. GitHub Actions builds the image and rolls it out
  (`.github/workflows/azure.yml`).
- **The website** (`frontend/`, the React dashboard) is a static site on
  **Azure Static Web Apps** (Free plan). GitHub Actions builds it and uploads
  it (`.github/workflows/azure-frontend.yml`).

Everything in Azure is named after the project name **`rep-tell`** (not the
GitHub repository `Rep-Intel`):

| What | Name |
|---|---|
| Resource group (only this project) | `rep-tell` |
| Container app (the backend) | `rep-tell` (in the shared environment `purva-bot-env`) |
| Container registry | `reptell82aaf9d4` |
| Image | `reptell82aaf9d4.azurecr.io/rep-tell:<commit>-<attempt>` |
| Website (Static Web App) | `rep-tell-web` |
| Identity GitHub uses to deploy | `rep-tell-github` |
| Settings in `.env.azure` | `KEY_rep_tell` (e.g. `GEMINI_API_KEY_rep_tell`) |

The setup steps below run in **Azure Cloud Shell** (it already has `az`, `git`,
`gh` and `jq`). You run them once. After that, deploys happen by themselves.

---

## Before you start

**1. Your Azure account needs Owner rights.** The account that runs the
scripts must be **Owner** of subscription `82aaf9d4-d161-4dab-8ecf-dff34de35353`
(or **Contributor** plus **User Access Administrator**). Contributor alone can
create everything but can't give out access, and the scripts do that. You
would then see `AuthorizationFailed ... Microsoft.Authorization/roleAssignments/write`.

Check what you have (in Cloud Shell):

```bash
az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" --all -o table
```

You need a line with `Owner` (or both `Contributor` and `User Access
Administrator`) whose scope is `/subscriptions/82aaf9d4-...`. If it's missing,
the subscription's Owner adds it: Azure portal -> **Subscriptions** -> the
subscription -> **Access control (IAM)** -> **Add** -> **Add role assignment**
-> pick the role -> **Members** -> your account -> **Review + assign**.

A role that was *just* added can take a few minutes to work. Wait, or run
`az login` in the same Cloud Shell tab. You don't need to start over.

**2. Keep the Cloud Shell tab open until you're done.** Cloud Shell can forget
files when the session ends (especially an "ephemeral" session), and
`.env.azure` (your settings file) exists only there.

**3. The deploy files must already be on `main`.** Check on GitHub that the
repository has a `deploy` folder and `.github/workflows/azure.yml` on `main`.
Whoever set this up pushes those first.

**4. You need push access to the repository** (be a collaborator on
`maanyagv/Rep-Intel`). You'll push one small file at the end. The repository
is **public**: anything committed, including the commit email, is visible to
everyone. The steps below use GitHub's private "noreply" email.

**5. Have the API keys ready** (see "Settings" below). Rep-Tell isn't hosted
anywhere yet, so there is no service to copy them from: they come from the
developer's local `.env` file, or you type them in. None is strictly
required; without the Gemini and YouTube keys the app does less.

---

## Setup, step by step

Open Cloud Shell: <https://shell.azure.com> (choose **Bash**).

### 1. Get the code

Sign in to GitHub (choose GitHub.com, HTTPS, and "Login with a web browser";
copy the code it shows):

```bash
gh auth login
```

```bash
gh repo clone maanyagv/Rep-Intel
```

```bash
cd Rep-Intel
```

The folder is named after the repository (`Rep-Intel`), not the project name.

*Already cloned it before?* Go into it and update it instead:

```bash
cd ~/Rep-Intel && git checkout main && git pull
```

Check the deploy files are there (you should see `azure.sh`, `github-setup.sh`,
`azure-frontend.sh`, `env-import.sh` and others):

```bash
ls deploy
```

### 2. Set your git name and email (once)

Cloud Shell has none. These use your GitHub name and the private noreply
email, so your real email isn't published:

```bash
git config user.name "$(gh api user --jq '.name // .login')"
```

```bash
git config user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
```

### 3. Collect the settings into `.env.azure`

The app's API keys go into a file called `.env.azure` in the `Rep-Intel`
folder. It is **never committed** (git ignores it) and only you can read it.

**Option A: type them in.** The script asks for each key in turn and says
where to get it. Typing is hidden; paste with right-click or Ctrl+Shift+V,
then Enter. Just Enter skips a key (or keeps the value it already has):

```bash
bash deploy/env-import.sh
```

**Option B: from the developer's local `.env` file.** Have them send it to you
privately (never by email or chat in plain text). Upload it to Cloud Shell
(the **Manage files** -> **Upload** button; it lands in your home folder),
then:

```bash
bash deploy/env-import.sh ~/.env
```

Afterwards delete the uploaded copy:

```bash
rm ~/.env
```

Either way, the script never prints a value. It renames every setting with
the project suffix (`GEMINI_API_KEY` becomes `GEMINI_API_KEY_rep_tell`), and
it leaves out things Azure doesn't need: `PORT`, the `DB_...` lines (the app
never uses a database), website settings (`VITE_...`), placeholders such as
`your_gemini_api_key`, and empty or multi-line values. At the end it lists
what it left out and which recommended keys are still missing.

**Check the file.** Open it:

```bash
nano .env.azure
```

Every line looks like `NAME_rep_tell=value`. Fix or add lines as needed. In
nano, paste with right-click or **Ctrl+Shift+V**. Save with **Ctrl+O** then
**Enter**, and exit with **Ctrl+X**.

To see just the names (no values):

```bash
cut -d= -f1 .env.azure
```

**If it imported nothing useful** (for example the `.env` file only had the
placeholders from `.env.example`): get each key from where it was created
(the table in "Settings" says where), or from the app's developer, and add
the lines by hand. The name always ends in `_rep_tell`, e.g.
`GEMINI_API_KEY_rep_tell=AIza...`. Then make sure only you can read the file:

```bash
chmod 600 .env.azure
```

### 4. Create the backend in Azure

First a dry run. It shows what it would do and changes nothing (secret values
are shown as `***`):

```bash
DRY_RUN=1 bash deploy/azure.sh
```

Then for real (takes a few minutes):

```bash
bash deploy/azure.sh
```

It creates the resource group `rep-tell`, the registry, and the container app
(running a placeholder page until the first deploy), and loads your settings
into it. It writes the backend's address into `deploy/azure-deploy.conf`.

- **`InternalServerError`**: Azure sometimes says this even though it worked.
  Just run the same command again. It picks up where it stopped.
- **`AuthorizationFailed`**: your account lacks a role (see "Before you
  start"). The script says which one. If the role was just added it keeps
  retrying for a couple of minutes; if it still fails, wait a few minutes (or
  run `az login`) and run the command again.
- **A warning that a setting is missing** tells you what won't work without it.
  Add the line to `.env.azure` and run `bash deploy/azure.sh` again.

### 5. Let GitHub deploy

```bash
bash deploy/github-setup.sh
```

This creates the identity `rep-tell-github` that GitHub Actions signs in with
(no password is stored anywhere: Azure trusts only GitHub runs on `main` of
this repository). It writes its IDs into `deploy/azure-deploy.conf`.

### 6. Create the website

```bash
bash deploy/azure-frontend.sh
```

This creates the Static Web App `rep-tell-web` (Free) and writes its address,
and the backend address the website must call, into
`deploy/azure-deploy.conf`. At the end it prints **one git command**.

(No backend setting changes for the new website address: the backend accepts
requests from any website, so you don't need to rerun `azure.sh`.)

### 7. Publish the config file (starts the first deploys)

Run the command `azure-frontend.sh` printed. It looks like this:

```bash
git add deploy/azure-deploy.conf && git commit -m "Azure: deploy settings for Rep-Tell" && git push
```

If git asks for a username/password, run this once, then the command again:

```bash
gh auth setup-git
```

### 8. Watch it and open the app

That push starts two GitHub Actions runs: **Deploy to Azure** (backend) and
**Deploy website to Azure**. Watch them:

```bash
gh run watch --repo maanyagv/Rep-Intel
```

(it asks which run to watch; or open the repository on GitHub -> **Actions**).
Each takes about 5 minutes. When both are green:

- open the website: the `WEBSITE_URL=` line in `deploy/azure-deploy.conf`,
  e.g. `https://<words>.azurestaticapps.net`;
- the backend's health page: the `BACKEND_URL=` address plus `/api/health`,
  e.g. `https://rep-tell.<something>.centralindia.azurecontainerapps.io/api/health`.
  It should say `"status": "ok"`.

To see both addresses:

```bash
grep -E '^(WEBSITE_URL|BACKEND_URL)=' deploy/azure-deploy.conf
```

---

## Settings

Names follow one rule, so settings of different projects can never clash:

| In `.env.azure` | Secret in Azure (portal) | What the app reads |
|---|---|---|
| `KEY_rep_tell=value` | `key-rep-tell` (lower-case, `_` -> `-`) | `KEY` |

For example `GEMINI_API_KEY_rep_tell` is stored as the secret
`gemini-api-key-rep-tell`, and the app gets
`GEMINI_API_KEY=secretref:gemini-api-key-rep-tell`. `PORT` is always `8080`
and set by the script.

| `.env.azure` name | Secret | Env var | Needed? | Where to get it |
|---|---|---|---|---|
| `GEMINI_API_KEY_rep_tell` | `gemini-api-key-rep-tell` | `GEMINI_API_KEY` | recommended: AI sentiment for new mentions (otherwise simple keyword rules) | Google AI Studio -> Get API key (aistudio.google.com/apikey) |
| `YOUTUBE_API_KEY_rep_tell` | `youtube-api-key-rep-tell` | `YOUTUBE_API_KEY` | recommended: without it no YouTube videos are collected | Google Cloud console -> APIs & Services -> Credentials -> API key (enable "YouTube Data API v3") |
| `NEWS_API_KEY_rep_tell` | `news-api-key-rep-tell` | `NEWS_API_KEY` | optional (news also comes from Google News RSS) | newsapi.org -> Account |
| `REDDIT_CLIENT_ID_rep_tell` | `reddit-client-id-rep-tell` | `REDDIT_CLIENT_ID` | optional, together with the next one | reddit.com/prefs/apps -> create a "script" app |
| `REDDIT_CLIENT_SECRET_rep_tell` | `reddit-client-secret-rep-tell` | `REDDIT_CLIENT_SECRET` | optional, together with the one above | same app |
| `BLUESKY_HANDLE_rep_tell` | `bluesky-handle-rep-tell` | `BLUESKY_HANDLE` | optional, together with the next one | your Bluesky handle, e.g. `name.bsky.social` |
| `BLUESKY_APP_PASSWORD_rep_tell` | `bluesky-app-password-rep-tell` | `BLUESKY_APP_PASSWORD` | optional, together with the one above | bsky.app -> Settings -> Privacy and security -> App passwords |

`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` and `DB_PASSWORD` from
`.env.example` are **not needed**: the running app never uses a database.

**Website settings** are public (they end up in the browser's JavaScript) and
live in `deploy/azure-deploy.conf`, not in `.env.azure`:

| Config line | Comes from |
|---|---|
| `WEB_ENV_VITE_API_URL` | `BACKEND_URL` (copied by `azure-frontend.sh`) |

The website's code currently has `http://127.0.0.1:8000` written in as the
backend address. The website workflow swaps that for `WEB_ENV_VITE_API_URL`
in the built files (the code itself isn't changed).

**Watch the API quotas.** The backend collects from every source every
30 seconds, around the clock. The free YouTube quota (10,000 units a day; one
search costs 100) and NewsAPI's free plan (100 requests a day) run out early
each day, after which those sources are skipped until the quota resets. If
someone also runs the app locally with the same keys, both share that quota.

### Changing a setting later

- **Easiest:** edit `.env.azure` in Cloud Shell (`nano .env.azure`), then run
  `bash deploy/azure.sh`. It updates only what changed and restarts the app
  with the new values. If it prints a git command, run that too.
- **Or in the Azure portal:** Container Apps -> `rep-tell` -> **Secrets** ->
  edit the secret, then **Revisions and replicas** -> **Restart**. (If you
  later rerun `azure.sh`, `.env.azure` wins, so keep it up to date.)
- **Website settings:** edit the `WEB_ENV_` lines in
  `deploy/azure-deploy.conf`, then commit and push. That rebuilds the site.
- **Size** (CPU/memory): edit `CPU=` and `MEMORY=` in
  `deploy/azure-deploy.conf` (valid pairs: 0.5/1Gi, 0.75/1.5Gi, 1/2Gi), run
  `bash deploy/azure.sh`, then commit and push the file. Keep
  `MIN_REPLICAS=1` and `MAX_REPLICAS=1` (see "Good to know").

---

## Switching users over to the new address

Rep-Tell isn't hosted anywhere today (it runs on people's own computers, at
`http://127.0.0.1:8000` and the Vite dev server), so there is nothing to turn
off and no old address to redirect:

1. **Tell people the website address** (`WEBSITE_URL=` in
   `deploy/azure-deploy.conf`). It is the only address they need; the
   website calls the backend by itself.
2. **CORS:** nothing to do. The backend accepts requests from any website
   (`allow_origins=["*"]` in `backend/main.py`).
3. **No sign-in, emailed links or QR codes** depend on the address, so
   nothing else changes.
4. The website's Settings page still *shows* "Backend: 127.0.0.1:8000" (that
   text is written in the code); it really uses the Azure backend.
5. **Data is separate.** The Azure backend starts from the dataset committed
   in `backend/data/` and collects on its own; it doesn't see what anyone
   collected locally, and vice versa.

---

## Good to know

- **Collected data doesn't survive a restart.** The backend keeps its data in
  JSON files inside the container (`backend/data/`). Every deploy, settings
  change or restart starts again from the files committed in the repository,
  so mentions collected since then, and alerts someone deleted, are gone. To
  keep data across deploys the code would need a database or Azure storage.
- **Always on, exactly one copy.** The collector loop runs inside the
  backend, so `MIN_REPLICAS=1` (it must keep running when nobody looks) and
  `MAX_REPLICAS=1` (a second copy would collect twice and show different data
  depending on which copy answers).

## What is shared with other projects (and what isn't)

- The **Container Apps environment** `purva-bot-env` (group `purva-bot`) is
  shared: the free trial allows only one environment in total. This app only
  *joins* it. The scripts never change it. Rep-Tell's backend logs go to that
  environment's Log Analytics workspace. If that environment were ever
  deleted, this app would be deleted with it.
- One **custom role**, "Container Apps environment join (purva-bot-env)", is
  shared by all projects. It lets a project's deploy identity add its app to
  the environment, nothing else.
- Everything else is Rep-Tell's own, in group `rep-tell`: registry, app,
  website, deploy identity, settings. Settings can't clash with other
  projects' because every name ends in `_rep_tell` / `-rep-tell`, and
  `azure.sh` refuses any `.env.azure` line that doesn't.
- `rep-tell-github` may only: manage group `rep-tell` (Contributor), push
  images to `reptell82aaf9d4` (AcrPush), and join the shared environment (the
  shared role). Nothing on the `purva-bot` group, nothing on the subscription.

## Costs (roughly, per month)

- Container registry Basic: about **US$5**.
- Backend, always on at 0.5 vCPU / 1 GiB: about **US$12** if it were mostly
  idle, but the collector loop wakes it every 30 seconds, so expect roughly
  **US$15–25**. At 0.75 vCPU / 1.5 GiB (snappier with several viewers) add
  about half again.
- Website (Static Web Apps Free): **US$0**.
- Logs: pennies.
- Azure's monthly free Container Apps allowance is shared by all apps in the
  subscription, so it may already be used up by the others.

## Removing it

This deletes everything Rep-Tell has in Azure (backend, website, registry,
deploy identity):

```bash
az group delete -n rep-tell
```

**Never** delete the `purva-bot` group, the `purva-bot-env` environment or
the shared "Container Apps environment join (purva-bot-env)" role. Other
projects use them.

---

## Reference

- `deploy/azure-deploy.conf`: all non-secret settings (committed). The
  workflows read only this file; there are no GitHub Actions variables or
  secrets.
- `deploy/env-import.sh`: writes `.env.azure` (typed in, or from a `.env` file).
- `deploy/azure.sh`: backend resources and settings. `DRY_RUN=1` to preview.
- `deploy/github-setup.sh`: the deploy identity for GitHub Actions.
- `deploy/azure-frontend.sh`: the Static Web App and website settings.
- `deploy/lib.sh`: shared helpers for the scripts.
- `deploy/Dockerfile` (+ `Dockerfile.dockerignore`): the backend image
  (Python 3.12, non-root, one uvicorn worker, port 8080).
- `deploy/staticwebapp.config.json`: website routing: every page path serves
  the app, a missing `/assets/...` file stays 404, hashed files are cached for
  a year, everything else is re-checked on each visit.
- `.github/workflows/azure.yml`: build, push, roll out, then wait until the
  new version answers on `/api/health`.
- `.github/workflows/azure-frontend.yml`: build the website, point it at the
  backend, upload it, then check the live site.
