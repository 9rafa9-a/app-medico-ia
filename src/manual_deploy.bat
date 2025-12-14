@echo off
echo === Manual Deployment ===
git add .
git commit -m "Fix CI: Remove redundant copy steps in build.yml"
git push
echo === Done! Check GitHub Actions ===
pause
