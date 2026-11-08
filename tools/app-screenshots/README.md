# Screenshots for the app guide

These scripts rebuild the screenshots in `vignettes/app-events/` for the article "Tailoring
calibration to the largest events in the app". Rerun them when the app's look changes.

From this folder, with pdmS7, shiny, Node.js, Playwright and Python's Pillow installed:

1. `Rscript build.R` builds the demo project in `demo-brook/`.
2. `Rscript serve.R &` serves the app on port 8765.
3. `mkdir -p shots && node shoot.js` drives the app in a headless browser and saves the
   screenshots in `shots/`.
4. `python3 crop.py` crops them into `vignettes/app-events/`.
5. Stop the server, and delete `demo-brook/` and `shots/`.

`shoot.js` assumes the entry ids the build gives: the last automatic stage is 0006, the trial
0009 and the refit 0010. If the build changes, check them, and check that the numbers quoted
in the article still match the screenshots.
