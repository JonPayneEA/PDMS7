# Serves the app on the demo project at http://127.0.0.1:8765 for shoot.js.
suppressMessages(library(pdmS7))
options(pdmS7.user = "A Hydrologist", pdmS7.role = "custodian")
shiny::runApp(calibration_app("demo-brook"), port = 8765, launch.browser = FALSE)
