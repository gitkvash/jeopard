# Auto-Deployment Rule for Question Packages and Trivia Content

Whenever question packages or clues are added, edited, or validated in this repository:
1. Always run package validation (`python src/merge_packets.py --check` or `python src/validate_packets.py`).
2. Run `python src/merge_packets.py` to synchronize `data/pilot.json`, `data/packets_all.json`, and `backend/src/main/resources/pilot.json`.
3. **Immediately deploy the changes to the live production server (Oracle VM):**
   ```bash
   & "C:\Program Files\Git\bin\bash.exe" deploy/oracle/deploy.sh ubuntu@158.180.18.180 --backend-only
   ```
   (Or full deploy without `--backend-only` if frontend web client assets were changed).
4. Verify on the live server (`https://jeopard-kvasho.duckdns.org`) that the changes are live and healthy.
