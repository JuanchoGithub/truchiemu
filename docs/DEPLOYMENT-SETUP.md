# GitHub Pages Deployment Setup

## Problem Analysis
The issue is that GitHub Pages isn't configured to automatically build and deploy your Jekyll site from the `docs/` directory.

## Solution Implemented
Created `.github/workflows/deploy-pages.yml` - A GitHub Actions workflow that:
- Automatically builds Jekyll site on every push to main/master branch
- Deploys to GitHub Pages using the official actions
- Forces rebuild by clearing caches and using fresh builds

## Required GitHub Settings Configuration

You **must** complete these steps in GitHub:

### 1. Enable GitHub Pages
1. Go to your repository on GitHub
2. Click **Settings** → **Pages** (in the left sidebar)
3. Under "Build and deployment", set:
   - **Source**: "GitHub Actions"
   - **Custom domain**: (leave blank unless you have one)

### 2. Verify Repository Settings
- Ensure repository is **public** (GitHub Pages works best with public repos)
- Verify the workflow file was pushed: `.github/workflows/deploy-pages.yml`

### 3. Deployment Process
Once configured:
1. Push any change to trigger the workflow
2. Go to **Actions** tab to monitor deployment progress
3. After successful deployment, visit:
   - https://juanchogithub.github.io/truchiemu/getting-started
   - https://juanchogithub.github.io/truchiemu/features
   - https://juanchogithub.github.io/truchiemu/systems

## Expected Behavior
- **Before**: Individual .html files returning 404
- **After**: Clean URLs without .html extension working correctly:
  - `/getting-started` instead of `/getting-started.html`
  - `/features` instead of `/features.html`
  - `/systems` instead of `/systems.html`

## Troubleshooting
If pages still return 404 after deployment:

1. **Check workflow logs**: Go to Actions tab, click on the workflow run
2. **Verify permalink structure**: The `_config.yml` uses `permalink: /:name/` which strips .html
3. **Clear browser cache**: Try hard refresh (Cmd+Shift+R on Mac)
4. **Wait 5-10 minutes**: GitHub Pages can take time to propagate

## Local Testing (Optional)
To test Jekyll build locally:
```bash
cd docs
bundle install
bundle exec jekyll serve
# Visit http://localhost:4000/truchiemu/
```

## Summary
The workflow will automatically:
- Build on every push to docs/** files
- Deploy to GitHub Pages within minutes
- Fix the 404 errors for getting-started.html, features.html, and systems.html
