# Netlify Zero-Credit Deployment Guide

To deploy your dashboards to Netlify without touching the AI agent box or burning platform credits:

## One-Time Setup (GitHub Connection)
1. Create a new empty repository on GitHub (e.g., `cass-dashboards`).
2. Run these commands in your terminal (or I can run them for you if you provide your repo URL):
   ```bash
   cd "/rool-drive/Misc/Dashboards/Netlify Deploy"
   git remote add origin https://github.com/YOUR_USERNAME/cass-dashboards.git
   git branch -M main
   git push -u origin main
   ```
3. In Netlify, click **"Add new site"** -> **"Import an existing project"** -> connect to your GitHub and select `cass-dashboards`. Set the publish directory to root (`/`).

## Ongoing Workflow
Whenever we update the intelligence board or command dashboard:
1. I automatically sync the files into this folder and commit them to git.
2. You (or a push helper) simply run:
   ```bash
   cd "/rool-drive/Misc/Dashboards/Netlify Deploy"
   git push
   ```
3. Netlify builds it instantly as a static site. **Zero AI credits burned, zero file renaming needed.**
